# frozen_string_literal: true

require "faye/websocket"
require "eventmachine"
require_relative "configuration"
require_relative "connection_status"

module Ibkr
  module WebSocket
    # WebSocket connection manager handling connection lifecycle, authentication,
    # and state management for IBKR WebSocket API.
    #
    # Manages:
    # - Connection establishment and teardown
    # - Authentication flow
    # - Connection state tracking
    # - Heartbeat and keep-alive
    # - Connection health monitoring
    # - Integration with reconnection strategy
    #
    class ConnectionManager
      include Ibkr::WebSocket::EventEmitter

      # Connection states
      STATES = %i[
        disconnected
        connecting
        connected
        authenticating
        authenticated
        disconnecting
        error
        reconnecting
      ].freeze

      defines_events :state_changed, :connected, :authenticated, :disconnected,
        :error, :message_received, :heartbeat

      attr_reader :state, :websocket, :last_ping_at, :last_pong_at, :connection_id,
        :heartbeat_interval, :connection_timeout

      # @param websocket_client [Ibkr::WebSocket::Client] Parent WebSocket client
      def initialize(websocket_client)
        @websocket_client = websocket_client
        @state = :disconnected
        @websocket = nil
        @authentication = Authentication.new(websocket_client.ibkr_client)
        @last_ping_at = nil
        @last_pong_at = nil
        @connection_id = nil
        @heartbeat_timer = nil
        @heartbeat_interval = Configuration::HEARTBEAT_INTERVAL
        @connection_timeout = Configuration::CONNECTION_TIMEOUT

        initialize_events
      end

      # Establish WebSocket connection to IBKR
      #
      # @return [Boolean] True if connection initiated successfully
      # @raise [ConnectionError] If connection fails to start
      def connect
        return true if connected? || connecting?

        change_state(:connecting)

        begin
          ensure_eventmachine_running
          establish_websocket_connection
          true
        rescue AuthenticationError => e
          change_state(:error)
          raise e  # Re-raise authentication errors without converting them
        rescue => e
          change_state(:error)
          raise ConnectionError.connection_failed(
            "Failed to establish WebSocket connection: #{e.message}",
            context: {
              endpoint: @authentication.websocket_endpoint,
              websocket_url: @authentication.websocket_endpoint,
              account_id: @websocket_client.account_id
            },
            cause: e
          )
        end
      end

      # Disconnect from WebSocket server
      #
      # @param code [Integer] WebSocket close code (default: 1000 - normal closure)
      # @param reason [String] Reason for disconnection
      # @param stop_eventmachine [Boolean] Whether to stop EventMachine (default: false for console usage)
      # @return [Boolean] True if disconnection initiated
      def disconnect(code: 1000, reason: "Client disconnecting", stop_eventmachine: false)
        return true if disconnected?

        change_state(:disconnecting)

        stop_heartbeat

        if @websocket
          @websocket.close(code, reason)
          @websocket = nil
        end

        # Optionally stop EventMachine (usually not desired in console/REPL)
        if stop_eventmachine && EventMachine.reactor_running?
          EventMachine.stop
          @em_thread&.join if @em_thread&.alive?
          @em_thread = nil
        end

        change_state(:disconnected)
        emit(:disconnected, code: code, reason: reason)

        true
      end

      # Check if WebSocket is connected
      #
      # @return [Boolean] True if connected to WebSocket server
      def connected?
        (@state == :connected || @state == :authenticated) && @websocket&.ready_state == Faye::WebSocket::API::OPEN
      end

      # Check if WebSocket is authenticated
      #
      # @return [Boolean] True if connected and authenticated
      def authenticated?
        @state == :authenticated && @authentication.authenticated?
      end

      # Check if connection is in progress
      #
      # @return [Boolean] True if currently connecting
      def connecting?
        @state == :connecting
      end

      # Check if disconnected
      #
      # @return [Boolean] True if disconnected
      def disconnected?
        @state == :disconnected
      end

      # Get connection health status
      #
      # @return [Boolean] True if connection is healthy
      def connection_healthy?
        return false unless connected?
        return false if heartbeat_stale?
        true
      end

      # Send message through WebSocket connection
      #
      # @param message [Hash] Message to send
      # @return [Boolean] True if message sent successfully
      # @raise [ConnectionError] If not connected or send fails
      def send_message(message)
        unless connected?
          raise ConnectionError.connection_failed(
            "Cannot send message - WebSocket not connected (state: #{@state})",
            context: {
              state: @state,
              message_type: message[:type],
              websocket_ready_state: @websocket&.ready_state,
              websocket_nil: @websocket.nil?
            }
          )
        end

        begin
          @websocket.send(message.to_json)
          true
        rescue => e
          raise ConnectionError.connection_failed(
            "Failed to send WebSocket message: #{e.message}",
            context: {message_type: message[:type]},
            cause: e
          )
        end
      end

      # Send ping to server for heartbeat
      #
      # @return [Boolean] True if ping sent successfully
      def ping
        return false unless connected?

        @last_ping_at = Time.now
        send_message(type: "ping", timestamp: @last_ping_at.to_f)
      rescue => e
        emit(:error, e)
        false
      end

      # Send IBKR-specific WebSocket ping with topic "tic"
      #
      # @return [Boolean] True if ping sent successfully
      def send_websocket_ping
        return false unless @websocket

        begin
          @websocket.send(Configuration::IBKR_PING_MESSAGE)
          true
        rescue => e
          emit(:error, e)
          false
        end
      end

      # Get connection statistics
      #
      # @return [ConnectionStatus] Connection status object
      def connection_stats
        ConnectionStatus.new(
          state: @state,
          connected: connected?,
          authenticated: authenticated?,
          healthy: connection_healthy?,
          connection_id: @connection_id,
          uptime: uptime,
          last_ping_at: @last_ping_at,
          last_pong_at: @last_pong_at,
          heartbeat_lag: heartbeat_lag,
          websocket_ready_state: @websocket&.ready_state,
          websocket_nil: @websocket.nil?,
          websocket_url: @authentication.websocket_endpoint
        )
      end

      # Get the WebSocket endpoint URL being used for debugging
      #
      # @return [String] The WebSocket URL being used for connection
      def websocket_url
        @authentication.websocket_endpoint
      end

      # Get connection uptime in seconds
      #
      # @return [Float, nil] Uptime in seconds, or nil if not connected
      def uptime
        return nil unless @connected_at
        Time.now - @connected_at
      end

      # Get the EventMachine thread status
      #
      # @return [Boolean] True if EventMachine thread is alive
      def em_thread_alive?
        @em_thread&.alive? || false
      end

      # Get the session token from authentication
      #
      # @return [String, nil] The session token if authenticated
      def session_token
        return nil unless authenticated?
        @authentication.session_token
      end

      # Send raw message through WebSocket (for IBKR-specific formats)
      #
      # @param message [String] Raw message to send
      # @return [Boolean] True if sent successfully
      def send_raw_message(message)
        return false unless @websocket

        begin
          @websocket.send(message)
          true
        rescue => e
          emit(:error, e)
          false
        end
      end

      # Set the connection as authenticated (called from message router)
      #
      # @return [void]
      def set_authenticated!
        change_state(:authenticated)
      end

      # Calculate heartbeat lag (called from Client)
      #
      # @return [Float, nil] Lag in seconds, or nil if no ping/pong yet
      def heartbeat_lag
        return nil unless @last_ping_at && @last_pong_at
        @last_pong_at - @last_ping_at
      end

      # Initiate authentication (called from Client)
      #
      # @return [void]
      def authenticate_connection
        change_state(:authenticating)

        # Send a WebSocket ping to activate the session
        # According to IBKR docs, ping with topic "tic" keeps session alive
        EventMachine.add_timer(1) do
          send_websocket_ping
        end
      end

      # Handle authentication response (called from MessageRouter)
      #
      # @param message [Hash] Auth response message
      # @return [void]
      def handle_auth_response(message)
        if @authentication.handle_auth_response(message)
          change_state(:authenticated)
          emit(:authenticated, connection_id: @connection_id)
          start_heartbeat
        end
      rescue AuthenticationError => e
        change_state(:error)
        emit(:error, e)
      end

      # Handle pong response (called from MessageRouter)
      #
      # @param message [Hash] Pong message
      # @return [void]
      def handle_pong_message(message)
        @last_pong_at = Time.now
        emit(:heartbeat, lag: heartbeat_lag)
      end

      private

      # Ensure EventMachine is running
      def ensure_eventmachine_running
        return if EventMachine.reactor_running?

        # Start EventMachine in a background thread for console/REPL usage
        @em_thread = Thread.new do
          EventMachine.run do
            # Keep EventMachine running - this block needs to stay open
            # EventMachine will process all WebSocket events in this reactor loop
          end
        end

        # Wait for EventMachine to start and be ready
        sleep Configuration::EM_START_WAIT_INTERVAL until EventMachine.reactor_running?

        # Give EventMachine a moment to fully initialize
        sleep Configuration::EM_INITIALIZATION_DELAY
      end

      # Establish the actual WebSocket connection
      def establish_websocket_connection
        endpoint = @authentication.websocket_endpoint
        headers = @authentication.connection_headers

        # Create connection tracking variables
        connection_established = false
        connection_error = nil

        # Ensure WebSocket is created within EventMachine reactor
        EventMachine.next_tick do
          @websocket = Faye::WebSocket::Client.new(endpoint, nil, headers: headers)

          setup_websocket_handlers

          # Mark connection as established once WebSocket is created
          connection_established = true

          # Set connection timeout
          EventMachine.add_timer(@connection_timeout) do
            if connecting?
              handle_connection_timeout
            end
          end
        rescue => e
          connection_error = e
          connection_established = true  # Set to true to break the wait loop
        end

        # Wait for the connection to be established or fail
        sleep Configuration::CONNECTION_ESTABLISHMENT_WAIT until connection_established

        # Raise error if connection failed
        if connection_error
          raise connection_error
        end
      end

      # Set up WebSocket event handlers
      def setup_websocket_handlers
        @websocket.on :open do |event|
          handle_websocket_open(event)
        end

        @websocket.on :message do |event|
          handle_websocket_message(event)
        end

        @websocket.on :close do |event|
          handle_websocket_close(event)
        end

        @websocket.on :error do |event|
          handle_websocket_error(event)
        end
      end

      # Handle WebSocket connection open
      def handle_websocket_open(event)
        @connected_at = Time.now
        @connection_id = SecureRandom.hex(8)

        change_state(:connected)
        emit(:connected, connection_id: @connection_id)

        # Start authentication process (now cookie-based)
        authenticate_connection
      end

      # Handle incoming WebSocket messages
      def handle_websocket_message(event)
        message = nil
        begin
          # First try to parse as JSON
          begin
            message = JSON.parse(event.data, symbolize_names: true)
          rescue JSON::ParserError
            # If not JSON, treat as raw message (IBKR sometimes sends non-JSON)
            message = {type: "raw", raw_message: event.data, message: event.data}
          end

          case message[:type]
          when "auth_response"
            handle_auth_response(message)
          when "pong"
            handle_pong_message(message)
          else
            emit(:message_received, message)
          end
        rescue => e
          message_type = message.is_a?(Hash) ? message[:type] : "unknown"
          emit(:error, MessageProcessingError.message_routing_failed(
            "Error processing WebSocket message",
            context: {
              message_type: message_type,
              raw_data: event.data
            },
            cause: e
          ))
        end
      end

      # Handle WebSocket connection close
      def handle_websocket_close(event)
        stop_heartbeat

        @websocket = nil
        @connected_at = nil
        @connection_id = nil

        change_state(:disconnected)
        emit(:disconnected, code: event.code, reason: event.reason)
      end

      # Handle WebSocket errors
      def handle_websocket_error(event)
        change_state(:error)

        error = ConnectionError.connection_failed(
          "WebSocket error: #{event.message}",
          context: {
            state: @state,
            connection_id: @connection_id
          }
        )

        emit(:error, error)
      end

      # Handle connection timeout
      def handle_connection_timeout
        change_state(:error)
        disconnect(code: 1006, reason: "Connection timeout")

        error = ConnectionError.connection_failed(
          "WebSocket connection timed out",
          context: {
            timeout: @connection_timeout,
            endpoint: @authentication.websocket_endpoint
          }
        )

        emit(:error, error)
      end

      # Start heartbeat timer
      def start_heartbeat
        return if @heartbeat_timer

        @heartbeat_timer = EventMachine.add_periodic_timer(@heartbeat_interval) do
          ping
        end

        # Send initial ping
        ping
      end

      # Stop heartbeat timer
      def stop_heartbeat
        if @heartbeat_timer
          @heartbeat_timer.cancel
          @heartbeat_timer = nil
        end
      end

      # Check if heartbeat is stale
      #
      # @return [Boolean] True if heartbeat is stale
      def heartbeat_stale?
        return false unless @last_ping_at
        return true unless @last_pong_at

        Configuration.heartbeat_stale?(@last_pong_at)
      end

      # Change connection state and emit event
      #
      # @param new_state [Symbol] New connection state
      def change_state(new_state)
        return if @state == new_state

        old_state = @state
        @state = new_state

        emit(:state_changed, from: old_state, to: new_state)
      end
    end
  end
end
