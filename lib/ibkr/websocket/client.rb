# frozen_string_literal: true

require "eventmachine"
require_relative "configuration"
require_relative "connection_status"

module Ibkr
  module WebSocket
    # Main WebSocket client providing real-time streaming capabilities for IBKR API.
    #
    # Features:
    # - Real-time market data streaming with Level I and Level II data
    # - Portfolio and account value streaming
    # - Order status and execution streaming
    # - Automatic connection management and reconnection
    # - Subscription management with rate limiting
    # - Event-driven architecture with comprehensive callbacks
    # - Integration with existing IBKR client authentication
    # - Performance monitoring and error handling
    #
    # @example Basic usage
    #   client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
    #   websocket = client.websocket
    #
    #   websocket.connect
    #   websocket.subscribe_market_data(["AAPL"], ["price", "volume"])
    #   websocket.on_market_data { |data| puts "#{data[:symbol]}: $#{data[:price]}" }
    #
    # @example Fluent interface
    #   client.websocket
    #     .connect
    #     .subscribe_market_data(["AAPL", "MSFT"], ["price"])
    #     .subscribe_portfolio("DU123456")
    #     .subscribe_orders("DU123456")
    #
    class Client
      include Ibkr::WebSocket::EventEmitter

      defines_events :connected, :authenticated, :disconnected, :error, :reconnected,
        :market_data, :portfolio_update, :order_update, :trade_data, :depth_data,
        :subscription_confirmed, :subscription_failed, :rate_limit_hit,
        :heartbeat, :system_message, :session_pending, :session_ready,
        :account_summary

      attr_reader :ibkr_client, :connection_manager, :subscription_manager,
        :message_router, :reconnection_strategy

      # Delegate methods to the underlying IBKR client
      def oauth_client
        @ibkr_client.oauth_client
      end

      def account_id
        @ibkr_client.account_id || @ibkr_client.instance_variable_get(:@default_account_id)
      end

      def live_mode?
        @ibkr_client.live_mode?
      end

      # Configuration access methods
      def reconnect_attempts
        @reconnection_strategy.reconnect_attempts
      end

      def heartbeat_interval
        @connection_manager.instance_variable_get(:@heartbeat_interval)
      end

      def connection_timeout
        @connection_manager.instance_variable_get(:@connection_timeout)
      end

      # @param ibkr_client [Ibkr::Client] Authenticated IBKR client
      def initialize(ibkr_client)
        raise ArgumentError, "IBKR client is required" if ibkr_client.nil?
        @ibkr_client = ibkr_client
        @connection_manager = ConnectionManager.new(self)
        @subscription_manager = SubscriptionManager.new(self)
        @message_router = MessageRouter.new(self)
        @reconnection_strategy = ReconnectionStrategy.new(self)
        @circuit_breaker = CircuitBreaker.new
        @message_errors = []

        # Initialize state tracking variables
        @authentication_timestamp = nil
        @last_auth_error = nil
        @reauthentication_required = false
        @last_heartbeat_response = nil
        @heartbeat_missed_count = 0
        @connection_start_time = nil

        initialize_events
        setup_event_routing
        setup_reconnection_strategy
      end

      # Establish WebSocket connection
      #
      # @return [self] Returns self for method chaining
      # @raise [ConnectionError] If connection fails
      def connect
        # Ensure main IBKR client is authenticated first
        unless @ibkr_client.authenticated?
          raise ConnectionError.connection_failed(
            "IBKR client must be authenticated before WebSocket connection",
            context: {
              operation: "websocket_connect_check",
              ibkr_authenticated: @ibkr_client.authenticated?
            }
          )
        end

        @connection_start_time = Time.now
        @connection_manager.connect
        self
      end

      # Disconnect from WebSocket server
      #
      # @param code [Integer] WebSocket close code (default: 1000)
      # @param reason [String] Disconnect reason
      # @param stop_eventmachine [Boolean] Whether to stop EventMachine (default: false)
      # @return [self] Returns self for method chaining
      def disconnect(code: 1000, reason: "Client disconnecting", stop_eventmachine: false)
        @reconnection_strategy.disable_automatic_reconnection
        @connection_manager.disconnect(code: code, reason: reason, stop_eventmachine: stop_eventmachine)
        self
      end

      # Check if WebSocket is connected
      #
      # @return [Boolean] True if connected to WebSocket server
      def connected?
        @connection_manager.connected?
      end

      # Check if WebSocket is authenticated
      #
      # @return [Boolean] True if connected and authenticated
      def authenticated?
        @connection_manager.authenticated?
      end

      # Get current connection state
      #
      # @return [Symbol] Current connection state
      def connection_state
        @connection_manager.state
      end

      # Check if connection is healthy
      #
      # @return [Boolean] True if connection is healthy
      def connection_healthy?
        @connection_manager.connection_healthy?
      end

      # Get detailed connection status for debugging
      #
      # @return [ConnectionStatus] Detailed connection status
      def connection_debug_status
        ConnectionStatus.new(
          state: @connection_manager.state,
          connected: connected?,
          authenticated: authenticated?,
          healthy: connection_healthy?,
          connection_id: @connection_manager.connection_id,
          uptime: @connection_manager.uptime,
          last_ping_at: @connection_manager.last_ping_at,
          last_pong_at: @connection_manager.last_pong_at,
          heartbeat_lag: @connection_manager.send(:heartbeat_lag),
          websocket_ready_state: @connection_manager.websocket&.ready_state,
          websocket_nil: @connection_manager.websocket.nil?,
          websocket_url: @connection_manager.websocket_url,
          eventmachine_running: EventMachine.reactor_running?,
          has_errors: @message_errors.any?
        )
      end

      # Subscribe to market data for symbols
      #
      # @param symbols [Array<String>] Stock symbols to subscribe to
      # @param fields [Array<String>] Data fields to receive (price, volume, bid, ask, etc.)
      # @return [String] Subscription ID
      # @raise [SubscriptionError] If subscription fails
      #
      # @example
      #   subscription_id = websocket.subscribe_market_data(["AAPL", "MSFT"], ["price", "volume"])
      #   websocket.on_market_data { |data| puts "#{data[:symbol]}: $#{data[:price]}" }
      #
      def subscribe_market_data(symbols, fields = ["price"])
        @subscription_manager.subscribe(
          channel: "market_data",
          symbols: Array(symbols),
          fields: Array(fields)
        )
      end

      # Subscribe to portfolio updates for account
      #
      # @param account_id [String] Account ID to monitor
      # @return [String] Subscription ID
      # @raise [SubscriptionError] If subscription fails
      #
      # @example
      #   subscription_id = websocket.subscribe_portfolio("DU123456")
      #   websocket.on_portfolio_update { |data| puts "Portfolio value: $#{data[:total_value]}" }
      #
      def subscribe_portfolio(account_id = nil)
        account_id ||= @ibkr_client.account_id

        @subscription_manager.subscribe(
          channel: "portfolio",
          account_id: account_id
        )
      end

      # Subscribe to order status updates for account
      #
      # @param account_id [String] Account ID to monitor
      # @return [String] Subscription ID
      # @raise [SubscriptionError] If subscription fails
      #
      # @example
      #   subscription_id = websocket.subscribe_orders("DU123456")
      #   websocket.on_order_update { |data| puts "Order #{data[:order_id]}: #{data[:status]}" }
      #
      def subscribe_orders(account_id = nil)
        account_id ||= @ibkr_client.account_id

        @subscription_manager.subscribe(
          channel: "orders",
          account_id: account_id
        )
      end

      # Subscribe to account summary updates
      #
      # @param account_id [String] Account ID to monitor
      # @param keys [Array<String>] Specific account summary keys to receive
      # @param fields [Array<String>] Specific fields to include in responses
      # @return [String] Subscription ID
      # @raise [SubscriptionError] If subscription fails
      #
      # @example
      #   subscription_id = websocket.subscribe_account_summary("DU123456")
      #   websocket.on_account_summary { |data| puts "Account Summary: #{data}" }
      #
      # @example With specific keys and fields
      #   websocket.subscribe_account_summary("DU123456",
      #     keys: ["AccruedCash-S", "ExcessLiquidity-S"],
      #     fields: ["currency", "monetaryValue"]
      #   )
      #
      def subscribe_account_summary(account_id = nil, keys: nil, fields: nil)
        account_id ||= @ibkr_client.account_id

        @subscription_manager.subscribe(
          channel: "account_summary",
          account_id: account_id,
          keys: keys,
          fields: fields
        )
      end

      # Unsubscribe from a specific subscription
      #
      # @param subscription_id [String] Subscription ID to remove
      # @return [Boolean] True if unsubscribed successfully
      def unsubscribe(subscription_id)
        @subscription_manager.unsubscribe(subscription_id)
      end

      # Unsubscribe from all active subscriptions
      #
      # @return [Integer] Number of subscriptions removed
      def unsubscribe_all(send_messages: true)
        @subscription_manager.unsubscribe_all(send_messages: send_messages)
      end

      # Get all active subscription IDs
      #
      # @return [Array<String>] List of active subscription IDs
      def active_subscriptions
        @subscription_manager.active_subscriptions
      end

      # Get subscribed symbols
      #
      # @return [Array<String>] List of subscribed symbols
      def subscribed_symbols
        market_data_subs = @subscription_manager.subscriptions_for_channel("market_data")
        market_data_subs.flat_map do |sub_id|
          sub = @subscription_manager.get_subscription(sub_id)
          sub[:symbols] || []
        end.uniq
      end

      # Send message through WebSocket connection
      #
      # @param message [Hash] Message to send
      # @return [Boolean] True if sent successfully
      # @raise [ConnectionError] If not connected or send fails
      def send_message(message)
        @connection_manager.send_message(message)
      end

      # Register event handler for market data updates
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_market_data(&block)
        on(:market_data, &block)
      end

      # Register event handler for portfolio updates
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_portfolio_update(&block)
        on(:portfolio_update, &block)
      end

      # Register event handler for order updates
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_order_update(&block)
        on(:order_update, &block)
      end

      # Register event handler for connection events
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_connected(&block)
        on(:connected, &block)
      end

      # Register event handler for disconnection events
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_disconnected(&block)
        on(:disconnected, &block)
      end

      # Register event handler for errors
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_error(&block)
        on(:error, &block)
      end

      # Register event handler for heartbeat events
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_heartbeat(&block)
        on(:heartbeat, &block)
      end

      # Register event handler for account summary updates
      #
      # @param block [Proc] Handler block
      # @return [self] Returns self for method chaining
      def on_account_summary(&block)
        on(:account_summary, &block)
      end

      # Check if currently rate limited
      #
      # @return [Boolean] True if rate limited
      def rate_limited?
        @subscription_manager.rate_limited?
      end

      # Get rate limit retry delay
      #
      # @return [Integer, nil] Seconds until rate limit resets
      def rate_limit_retry_after
        @subscription_manager.rate_limit_retry_after
      end

      # Check if reconnecting
      #
      # @return [Boolean] True if currently reconnecting
      def reconnecting?
        @reconnection_strategy.reconnect_attempts > 0
      end

      # Check if circuit breaker is open
      #
      # @return [Boolean] True if circuit breaker is open
      def circuit_breaker_open?
        @circuit_breaker.open?
      end

      # Check if authentication is rate limited
      #
      # @return [Boolean] True if auth rate limited
      def auth_rate_limited?
        @circuit_breaker.auth_rate_limited?
      end

      # Force reauthentication
      #
      # @return [Boolean] True if reauthentication initiated
      # @raise [CircuitBreakerError] If circuit breaker is open
      def reauthenticate
        if circuit_breaker_open?
          raise CircuitBreakerError.circuit_open(
            context: {operation: "reauthentication"}
          )
        end

        @connection_manager.send(:authenticate_connection)
      end

      # Get recent message errors
      #
      # @return [Array<Hash>] List of recent message errors
      def message_errors
        @message_errors.dup
      end

      # Get comprehensive statistics
      #
      # @return [Hash] WebSocket client statistics
      def statistics
        {
          connection: @connection_manager.connection_stats,
          subscriptions: @subscription_manager.subscription_statistics,
          message_routing: @message_router.statistics,
          reconnection: @reconnection_strategy.reconnection_statistics,
          circuit_breaker: @circuit_breaker.statistics,
          message_errors: @message_errors.size,
          eventmachine: eventmachine_status
        }
      end

      # Check EventMachine status
      #
      # @return [Hash] EventMachine status information
      def eventmachine_status
        {
          running: EventMachine.reactor_running?,
          thread_running: @connection_manager.instance_variable_get(:@em_thread)&.alive? || false
        }
      end

      # Stop EventMachine (useful for console cleanup)
      #
      # @return [Boolean] True if EventMachine was stopped
      def stop_eventmachine!
        disconnect(stop_eventmachine: true)
        true
      end

      # Enable automatic reconnection
      #
      # @return [self] Returns self for method chaining
      def enable_auto_reconnect
        @reconnection_strategy.enable_automatic_reconnection
        self
      end

      # Disable automatic reconnection
      #
      # @return [self] Returns self for method chaining
      def disable_auto_reconnect
        @reconnection_strategy.disable_automatic_reconnection
        self
      end

      # Fluent interface methods for chaining

      # Connect and subscribe to market data (fluent interface)
      #
      # @param symbols [Array<String>] Symbols to subscribe to
      # @param fields [Array<String>] Data fields to receive
      # @return [self] Returns self for method chaining
      def subscribe_to_market_data(symbols, fields = ["price"])
        connect unless connected?
        subscribe_market_data(symbols, fields)
        self
      end

      # Connect and subscribe to portfolio updates (fluent interface)
      #
      # @param account_id [String] Account ID (optional)
      # @return [self] Returns self for method chaining
      def subscribe_to_portfolio_updates(account_id = nil)
        connect unless connected?
        subscribe_portfolio(account_id)
        self
      end

      # Connect and subscribe to order status (fluent interface)
      #
      # @param account_id [String] Account ID (optional)
      # @return [self] Returns self for method chaining
      def subscribe_to_order_status(account_id = nil)
        connect unless connected?
        subscribe_orders(account_id)
        self
      end

      # Additional methods expected by specs

      # Get last error message
      #
      # @return [String, nil] Last error message
      def last_error
        return nil if @message_errors.empty?
        error_data = @message_errors.last
        error_data[:error]&.message || error_data[:message] || "Unknown error"
      end

      # Get session ID
      #
      # @return [String, nil] Current session ID
      def session_id
        # Try to get from connection manager state or authentication
        return nil unless @connection_manager.authenticated?
        @connection_manager.instance_variable_get(:@authentication)&.instance_variable_get(:@session_token)
      end

      # Get error count
      #
      # @return [Integer] Number of errors
      def error_count
        @message_errors.size
      end

      # Get authentication timestamp
      #
      # @return [Time, nil] Time of last authentication
      attr_reader :authentication_timestamp

      # Get last authentication error
      #
      # @return [String, nil] Last authentication error
      attr_reader :last_auth_error

      # Check if reauthentication is required
      #
      # @return [Boolean] True if reauthentication is required
      def reauthentication_required?
        @reauthentication_required || false
      end

      # Get last heartbeat response time
      #
      # @return [Time, nil] Time of last heartbeat response
      attr_reader :last_heartbeat_response

      # Get heartbeat missed count
      #
      # @return [Integer] Number of missed heartbeats
      def heartbeat_missed_count
        @heartbeat_missed_count || 0
      end

      # Get messages processed count
      #
      # @return [Integer] Number of messages processed
      def messages_processed
        @message_router.routing_statistics[:total_messages] || 0
      end

      # Get average message processing time
      #
      # @return [Float] Average processing time in seconds
      def average_message_processing_time
        times = @message_router.routing_statistics[:processing_times] || []
        return 0.0 if times.empty?
        times.sum.to_f / times.size
      end

      # Get messages per second
      #
      # @return [Float] Messages processed per second
      def messages_per_second
        return 0.0 unless @connection_start_time
        elapsed = Time.now - @connection_start_time
        return 0.0 if elapsed <= 0
        messages_processed.to_f / elapsed
      end

      # Get subscription errors
      #
      # @return [Array<String>] List of subscription IDs that have errors
      def subscription_errors
        @subscription_manager.subscription_errors
      end

      # Get last subscription error for a specific subscription
      #
      # @param subscription_id [String] Subscription ID
      # @return [Hash, nil] Error details or nil if no error
      def last_subscription_error(subscription_id)
        @subscription_manager.last_subscription_error(subscription_id)
      end

      # Get next reconnection delay
      #
      # @param attempt [Integer] Attempt number
      # @return [Float] Delay in seconds for next reconnection attempt
      def next_reconnect_delay(attempt)
        @reconnection_strategy.next_reconnect_delay(attempt)
      end

      # Get maximum reconnection delay
      #
      # @return [Float] Maximum delay in seconds
      def max_reconnect_delay
        @reconnection_strategy.instance_variable_get(:@max_delay)
      end

      private

      # Setup event routing between components
      def setup_event_routing
        # Forward connection manager events
        @connection_manager.on(:connected) { emit(:connected) }
        @connection_manager.on(:authenticated) { emit(:authenticated) }
        @connection_manager.on(:disconnected) do |data|
          # Clear all subscriptions on disconnect without sending messages
          @subscription_manager.unsubscribe_all(send_messages: false)
          emit(:disconnected, data)
        end
        @connection_manager.on(:error) { |error| handle_connection_error(error) }
        @connection_manager.on(:heartbeat) do |data|
          @last_heartbeat_response = Time.now
          emit(:heartbeat, data)
        end
        @connection_manager.on(:message_received) { |msg| @message_router.route(msg) }

        # Forward subscription manager events
        @subscription_manager.on(:subscription_confirmed) { |data| emit(:subscription_confirmed, data) }
        @subscription_manager.on(:subscription_failed) { |data| emit(:subscription_failed, data) }
        @subscription_manager.on(:rate_limit_hit) { |data| emit(:rate_limit_hit, data) }

        # Forward message router events
        @message_router.on(:routing_error) { |data| handle_message_error(data) }
        @message_router.on(:unknown_message_type) { |data| handle_unknown_message(data) }

        # Handle direct error events from message processing
        on(:error) { |error| handle_error_event(error) }

        # Handle session events
        on(:session_pending) { |data| handle_session_pending(data) }
        on(:session_ready) { |data| handle_session_ready(data) }
      end

      # Setup reconnection strategy
      def setup_reconnection_strategy
        @reconnection_strategy.enable_automatic_reconnection

        # Handle connection loss for reconnection
        @connection_manager.on(:disconnected) do |data|
          @reconnection_strategy.handle_connection_closed(
            code: data[:code],
            reason: data[:reason]
          )
        end

        # Handle successful reconnection
        @connection_manager.on(:authenticated) do
          if @reconnection_strategy.reconnect_attempts > 0
            @reconnection_strategy.handle_successful_reconnection
            restore_subscriptions_after_reconnection
            emit(:reconnected)
          end
        end
      end

      # Handle connection errors with circuit breaker
      def handle_connection_error(error)
        @circuit_breaker.record_failure

        # Capture error details for debugging
        error_info = {
          timestamp: Time.now,
          error: error,
          message: error.respond_to?(:message) ? error.message : error.to_s
        }
        @message_errors << error_info

        # Keep only last N errors for memory efficiency
        @message_errors.shift if @message_errors.size > Configuration::MAX_MESSAGE_ERRORS

        # Handle authentication-specific errors
        if error.is_a?(Ibkr::AuthenticationError) || error.to_s.include?("authentication") || error.to_s.include?("invalid_token")
          @last_auth_error = error_info[:message]
          @reauthentication_required = true
        end

        emit(:error, error)
      end

      # Handle message processing errors
      def handle_message_error(data)
        error_info = {
          timestamp: Time.now,
          error: data[:error],
          message: data[:message]
        }

        @message_errors << error_info

        # Keep only last N errors for memory efficiency
        @message_errors.shift if @message_errors.size > Configuration::MAX_MESSAGE_ERRORS

        emit(:error, data[:error])
      end

      # Handle unknown message types
      def handle_unknown_message(data)
        emit(:system_message, {
          type: "unknown_message_type",
          original_type: data[:type],
          message: data[:message]
        })
      end

      # Handle direct error events from message processing
      def handle_error_event(error)
        error_info = {
          timestamp: Time.now,
          error: error,
          message: error.respond_to?(:message) ? error.message : error.to_s
        }

        @message_errors << error_info

        # Keep only last N errors for memory efficiency
        @message_errors.shift if @message_errors.size > Configuration::MAX_MESSAGE_ERRORS
      end

      # Handle session pending message
      def handle_session_pending(data)
        # IBKR is waiting for session to be ready - this is normal
        # We can optionally log this or take action
      end

      # Handle session ready message
      def handle_session_ready(data)
        # Session is ready - we can now consider ourselves authenticated
        @authentication_timestamp = Time.now
        @reauthentication_required = false
        @connection_manager.set_authenticated!
        emit(:authenticated)
      end

      # Restore subscriptions after reconnection
      def restore_subscriptions_after_reconnection
        recovery_state = @subscription_manager.get_recovery_state
        return if recovery_state[:subscriptions].empty?

        result = @subscription_manager.restore_from_recovery_state(recovery_state)

        emit(:system_message, {
          type: "subscriptions_restored",
          restored: result[:restored],
          failed: result[:failed]
        })
      end

      # Simple circuit breaker implementation
      class CircuitBreaker
        def initialize(failure_threshold: Configuration::CIRCUIT_BREAKER_FAILURE_THRESHOLD,
          timeout: Configuration::CIRCUIT_BREAKER_TIMEOUT)
          @failure_threshold = failure_threshold
          @timeout = timeout
          @failure_count = 0
          @last_failure_time = nil
          @state = :closed
        end

        def record_failure
          @failure_count += 1
          @last_failure_time = Time.now

          if @failure_count >= @failure_threshold
            @state = :open
          end
        end

        def open?
          return false if @state == :closed

          if Time.now - @last_failure_time > @timeout
            @state = :closed
            @failure_count = 0
            false
          else
            true
          end
        end

        def auth_rate_limited?
          open?
        end

        def statistics
          {
            state: @state,
            failure_count: @failure_count,
            last_failure: @last_failure_time,
            threshold: @failure_threshold,
            timeout: @timeout
          }
        end
      end
    end
  end
end
