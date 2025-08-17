# frozen_string_literal: true

require "securerandom"
require_relative "configuration"

module Ibkr
  module WebSocket
    # WebSocket subscription manager handling subscription lifecycle,
    # rate limiting, and subscription state management.
    #
    # Features:
    # - Unique subscription ID generation
    # - Subscription metadata tracking
    # - Rate limiting and subscription limits
    # - Subscription recovery for reconnections
    # - Channel-based subscription grouping
    # - Symbol-based subscription filtering
    # - Subscription statistics and monitoring
    #
    class SubscriptionManager
      include Ibkr::WebSocket::EventEmitter

      defines_events :subscription_created, :subscription_confirmed, :subscription_failed,
        :subscription_removed, :rate_limit_hit

      # Default subscription limits
      DEFAULT_LIMITS = Configuration::DEFAULT_SUBSCRIPTION_LIMITS

      # Default rate limits (requests per minute)
      DEFAULT_RATE_LIMIT = Configuration::DEFAULT_RATE_LIMIT

      attr_reader :subscriptions, :rate_limited_until

      # @param websocket_client [Ibkr::WebSocket::Client] Parent WebSocket client
      def initialize(websocket_client)
        raise ArgumentError, "websocket_client is required" unless websocket_client

        @websocket_client = websocket_client
        @subscriptions = {}
        @subscription_limits = DEFAULT_LIMITS.dup
        @rate_limit = DEFAULT_RATE_LIMIT
        @rate_limited_until = nil
        @rate_limit_requests = []

        initialize_events
      end

      # Create a new subscription
      #
      # @param request [Hash] Subscription request parameters
      # @option request [String] :channel Channel type (market_data, portfolio, orders)
      # @option request [Array<String>] :symbols Symbols to subscribe to (for market_data)
      # @option request [Array<String>] :fields Data fields to receive
      # @option request [String] :account_id Account ID (for portfolio/orders)
      # @return [String] Unique subscription ID
      # @raise [SubscriptionError] If subscription fails or limits exceeded
      def subscribe(request)
        validate_subscription_request!(request)
        check_rate_limit!
        check_subscription_limits!(request[:channel])

        # Check for duplicate subscription
        existing_id = find_duplicate_subscription(request)
        return existing_id if existing_id

        subscription_id = generate_subscription_id
        subscription = create_subscription_record(subscription_id, request)

        @subscriptions[subscription_id] = subscription
        record_rate_limit_request

        send_subscription_message(subscription)
        emit(:subscription_created, subscription_id: subscription_id, request: request)

        subscription_id
      end

      # Remove a subscription
      #
      # @param subscription_id [String] Subscription ID to remove
      # @return [Boolean] True if subscription was removed
      def unsubscribe(subscription_id)
        subscription = @subscriptions.delete(subscription_id)
        return false unless subscription

        send_unsubscription_message(subscription_id, subscription)
        emit(:subscription_removed, subscription_id: subscription_id)

        true
      end

      # Remove all subscriptions
      #
      # @return [Integer] Number of subscriptions removed
      def unsubscribe_all(send_messages: true)
        count = @subscriptions.size

        if send_messages
          @subscriptions.keys.each do |subscription_id|
            unsubscribe(subscription_id)
          end
        else
          # Just clear subscriptions without sending messages (for disconnect cleanup)
          @subscriptions.each do |subscription_id, subscription|
            emit(:subscription_removed, subscription_id: subscription_id)
          end
          @subscriptions.clear
        end

        count
      end

      # Get subscription by ID
      #
      # @param subscription_id [String] Subscription ID
      # @return [Hash, nil] Subscription record or nil if not found
      def get_subscription(subscription_id)
        @subscriptions[subscription_id]
      end

      # Get current subscription count
      #
      # @return [Integer] Total number of subscriptions
      def subscription_count
        @subscriptions.size
      end

      # Get all active subscription IDs
      #
      # @return [Array<String>] List of active subscription IDs
      def active_subscriptions
        @subscriptions.select { |_, sub| sub[:status] == :active }.keys
      end

      # Get subscriptions for a specific channel
      #
      # @param channel [String] Channel name
      # @return [Array<String>] Subscription IDs for the channel
      def subscriptions_for_channel(channel)
        @subscriptions.select { |_, sub| sub[:channel] == channel }.keys
      end

      # Get subscriptions for a specific symbol
      #
      # @param symbol [String] Symbol name
      # @return [Array<String>] Subscription IDs that include the symbol
      def subscriptions_for_symbol(symbol)
        @subscriptions.select do |_, sub|
          sub[:symbols]&.include?(symbol)
        end.keys
      end

      # Get all active channels
      #
      # @return [Array<String>] List of active channel names
      def active_channels
        @subscriptions.values.map { |sub| sub[:channel] }.uniq
      end

      # Handle subscription response from server
      #
      # @param response [Hash] Server response
      # @option response [String] :subscription_id Subscription ID
      # @option response [String] :status Response status (success/error)
      # @option response [String] :error Error code (if status is error)
      # @option response [String] :message Error message (if status is error)
      # @option response [Integer] :retry_after Rate limit retry delay (if rate limited)
      # @return [void]
      def handle_subscription_response(response)
        subscription_id = response[:subscription_id]
        subscription = @subscriptions[subscription_id]

        return unless subscription

        case response[:status]
        when "success"
          handle_successful_subscription(subscription_id, response)
        when "error"
          handle_failed_subscription(subscription_id, response)
        end
      end

      # Get subscription statistics
      #
      # @return [Hash] Statistics about current subscriptions
      def subscription_statistics
        by_channel = Hash.new(0)
        by_status = Hash.new(0)

        @subscriptions.each do |_, sub|
          by_channel[sub[:channel]] += 1
          by_status[sub[:status]] += 1
        end

        {
          total: @subscriptions.size,
          by_channel: by_channel,
          by_status: by_status,
          active: by_status[:active],
          pending: by_status[:pending],
          error: by_status[:error]
        }
      end

      # Get subscription state for connection recovery
      #
      # @return [Hash] Recovery state containing active subscriptions
      def get_recovery_state
        active_subs = @subscriptions.select { |_, sub| sub[:status] == :active }

        {
          subscriptions: active_subs.map do |id, sub|
            {
              subscription_id: id,
              channel: sub[:channel],
              parameters: build_subscription_parameters(sub)
            }
          end
        }
      end

      # Restore subscriptions from recovery state
      #
      # @param recovery_state [Hash] Recovery state from previous session
      # @return [Hash] Result with counts of restored and failed subscriptions
      def restore_from_recovery_state(recovery_state)
        restored = 0
        failed = 0

        recovery_state[:subscriptions]&.each do |sub_data|
          request = {
            channel: sub_data[:channel],
            **sub_data[:parameters]
          }

          # Validate the request (same validation as subscribe method)
          validate_subscription_request!(request)

          # Use existing subscription ID if provided
          subscription_id = sub_data[:subscription_id] || generate_subscription_id
          subscription = create_subscription_record(subscription_id, request)

          @subscriptions[subscription_id] = subscription
          send_subscription_message(subscription)

          restored += 1
        rescue => e
          failed += 1
          emit(:subscription_failed,
            subscription_id: sub_data[:subscription_id],
            error: e.message)
        end

        {restored: restored, failed: failed}
      end

      # Get subscription errors
      #
      # @return [Array<String>] List of subscription IDs that have errors
      def subscription_errors
        @subscriptions.select { |_, sub| sub[:status] == :error }.keys
      end

      # Get last subscription error for a specific subscription
      #
      # @param subscription_id [String] Subscription ID
      # @return [Hash, nil] Error details or nil if no error
      def last_subscription_error(subscription_id)
        subscription = @subscriptions[subscription_id]
        return nil unless subscription && subscription[:status] == :error

        {
          error: subscription[:error],
          message: subscription[:error_message],
          subscription_id: subscription_id,
          timestamp: subscription[:updated_at] || subscription[:created_at]
        }
      end

      # Get maximum subscriptions allowed
      #
      # @return [Integer] Maximum total subscriptions
      def max_subscriptions
        @subscription_limits[:total]
      end

      # Get subscription limits per channel
      #
      # @return [Hash] Channel-specific subscription limits
      def max_subscriptions_per_channel
        @subscription_limits.except(:total)
      end

      # Get subscription rate limit
      #
      # @return [Integer] Maximum subscriptions per minute
      def subscription_rate_limit
        @rate_limit
      end

      # Check if currently rate limited
      #
      # @return [Boolean] True if rate limited
      def rate_limited?
        @rate_limited_until && Time.now < @rate_limited_until
      end

      # Get retry after time for rate limit
      #
      # @return [Integer, nil] Seconds to retry after, or nil if not rate limited
      def rate_limit_retry_after
        return nil unless rate_limited?
        (@rate_limited_until - Time.now).ceil
      end

      # Get rate limit reset time
      #
      # @return [Time, nil] Time when rate limit resets
      def rate_limit_resets_at
        @rate_limited_until
      end

      # Test configuration helper - provides public interface for test setup
      # This method is intentionally public to support testing without internal state access
      def configure_for_testing(limits: {}, rate_limit: nil)
        @subscription_limits = @subscription_limits.merge(limits) if limits.any?
        @rate_limit = rate_limit if rate_limit
        self
      end

      private

      # Generate unique subscription ID
      #
      # @return [String] Unique subscription ID
      def generate_subscription_id
        "sub_#{SecureRandom.hex(8)}"
      end

      # Create subscription record
      #
      # @param subscription_id [String] Subscription ID
      # @param request [Hash] Subscription request
      # @return [Hash] Subscription record
      def create_subscription_record(subscription_id, request)
        {
          id: subscription_id,
          channel: request[:channel],
          symbols: request[:symbols],
          fields: request[:fields],
          account_id: request[:account_id],
          status: :pending,
          created_at: Time.now,
          confirmed_at: nil,
          error: nil,
          error_message: nil
        }
      end

      # Find duplicate subscription
      #
      # @param request [Hash] Subscription request
      # @return [String, nil] Existing subscription ID or nil
      def find_duplicate_subscription(request)
        @subscriptions.find do |_, sub|
          sub[:channel] == request[:channel] &&
            sub[:symbols] == request[:symbols] &&
            sub[:fields] == request[:fields] &&
            sub[:account_id] == request[:account_id]
        end&.first
      end

      # Validate subscription request
      #
      # @param request [Hash] Subscription request
      # @raise [ArgumentError] If request is invalid
      def validate_subscription_request!(request)
        raise ArgumentError, "Channel is required" unless request[:channel]

        # Validate known channels
        valid_channels = ["market_data", "portfolio", "orders", "account_summary"]
        unless valid_channels.include?(request[:channel])
          raise ArgumentError, "Unknown channel: #{request[:channel]}"
        end

        case request[:channel]
        when "market_data"
          raise ArgumentError, "Symbols required for market_data" unless request[:symbols]&.any?
        when "portfolio", "orders", "account_summary"
          raise ArgumentError, "Account ID required for #{request[:channel]}" unless request[:account_id]
        end
      end

      # Check rate limit
      #
      # @raise [SubscriptionError] If rate limited
      def check_rate_limit!
        if rate_limited?
          raise SubscriptionError.rate_limited(
            context: {
              retry_after: rate_limit_retry_after,
              resets_at: @rate_limited_until
            }
          )
        end

        # Check request rate (requests per minute)
        recent_requests = @rate_limit_requests.select { |t| t > Time.now - 60 }

        if recent_requests.size >= @rate_limit
          raise SubscriptionError.rate_limited(
            context: {
              requests_per_minute: recent_requests.size,
              limit: @rate_limit
            }
          )
        end
      end

      # Check subscription limits
      #
      # @param channel [String] Channel being subscribed to
      # @raise [SubscriptionError] If limits exceeded
      def check_subscription_limits!(channel)
        # Check total limit
        if @subscriptions.size >= @subscription_limits[:total]
          raise SubscriptionError.limit_exceeded(
            "total",
            context: {
              current_count: @subscriptions.size,
              limit: @subscription_limits[:total]
            }
          )
        end

        # Check channel-specific limit
        channel_count = subscriptions_for_channel(channel).size
        channel_limit = @subscription_limits[channel.to_sym]

        if channel_limit && channel_count >= channel_limit
          raise SubscriptionError.limit_exceeded(
            channel,
            context: {
              current_count: channel_count,
              limit: channel_limit
            }
          )
        end
      end

      # Record rate limit request
      def record_rate_limit_request
        @rate_limit_requests << Time.now
        # Clean up old requests (keep only last hour)
        @rate_limit_requests.reject! { |t| t < Time.now - Configuration::RATE_LIMIT_HISTORY_DURATION }
      end

      # Send subscription message to WebSocket
      #
      # @param subscription [Hash] Subscription record
      def send_subscription_message(subscription)
        case subscription[:channel]
        when "account_summary"
          # IBKR account summary subscription format: ssd+{accountId}+{parameters}
          params = {
            keys: subscription[:keys] || Configuration::DEFAULT_ACCOUNT_SUMMARY_KEYS,
            fields: subscription[:fields] || Configuration::DEFAULT_ACCOUNT_SUMMARY_FIELDS
          }

          ibkr_message = Configuration::ACCOUNT_SUMMARY_SUBSCRIBE_FORMAT % [subscription[:account_id], params.to_json]
          @websocket_client.connection_manager.send_raw_message(ibkr_message)

        when "market_data"
          # Standard market data subscription format (to be implemented)
          message = {
            type: "subscribe",
            subscription_id: subscription[:id],
            channel: subscription[:channel],
            symbols: subscription[:symbols],
            fields: subscription[:fields]
          }
          @websocket_client.send_message(message)

        else
          # Standard subscription format
          message = {
            type: "subscribe",
            subscription_id: subscription[:id],
            channel: subscription[:channel]
          }

          # Add channel-specific parameters
          case subscription[:channel]
          when "portfolio", "orders"
            message[:account_id] = subscription[:account_id]
          end

          @websocket_client.send_message(message)
        end
      end

      # Send unsubscription message to WebSocket
      #
      # @param subscription [Hash] Subscription record
      def send_unsubscription_message(subscription_id, subscription)
        case subscription[:channel]
        when "account_summary"
          # IBKR account summary unsubscription format: usd+{accountId}
          ibkr_message = Configuration::ACCOUNT_SUMMARY_UNSUBSCRIBE_FORMAT % subscription[:account_id]
          @websocket_client.connection_manager.send_raw_message(ibkr_message)

        else
          # Standard unsubscription format for other channels
          message = {
            type: "unsubscribe",
            subscription_id: subscription_id
          }

          @websocket_client.send_message(message)
        end
      end

      # Handle successful subscription confirmation
      #
      # @param subscription_id [String] Subscription ID
      # @param response [Hash] Server response
      def handle_successful_subscription(subscription_id, response)
        subscription = @subscriptions[subscription_id]
        return unless subscription

        subscription[:status] = :active
        subscription[:confirmed_at] = Time.now
        subscription[:confirmation_latency] = Time.now - subscription[:created_at]

        emit(:subscription_confirmed, subscription_id: subscription_id)
      end

      # Handle failed subscription
      #
      # @param subscription_id [String] Subscription ID
      # @param response [Hash] Server error response
      def handle_failed_subscription(subscription_id, response)
        subscription = @subscriptions[subscription_id]
        return unless subscription

        subscription[:status] = :error
        subscription[:error] = response[:error]
        subscription[:error_message] = response[:message]

        # Handle rate limiting
        if response[:error] == "rate_limit_exceeded" && response[:retry_after]
          @rate_limited_until = Time.now + response[:retry_after]
          emit(:rate_limit_hit, retry_after: response[:retry_after])

          # Also emit as general error for client error tracking
          error_message = "#{response[:error]}: #{response[:message]}"
          error = SubscriptionError.new(
            error_message,
            context: {
              subscription_id: subscription_id,
              retry_after: response[:retry_after],
              error_type: response[:error]
            }
          )
          @websocket_client.emit(:error, error)
        end

        emit(:subscription_failed,
          subscription_id: subscription_id,
          error: response[:error],
          message: response[:message])
      end

      # Build subscription parameters for recovery
      #
      # @param subscription [Hash] Subscription record
      # @return [Hash] Parameters for recreating subscription
      def build_subscription_parameters(subscription)
        params = {}

        params[:symbols] = subscription[:symbols] if subscription[:symbols]
        params[:fields] = subscription[:fields] if subscription[:fields]
        params[:account_id] = subscription[:account_id] if subscription[:account_id]

        params
      end
    end
  end
end
