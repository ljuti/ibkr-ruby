# frozen_string_literal: true

require_relative "configuration"

module Ibkr
  module WebSocket
    # WebSocket message router responsible for parsing and routing incoming
    # messages to appropriate handlers based on message type and content.
    #
    # Features:
    # - Message type-based routing
    # - Subscription-based routing for data streams
    # - Error message handling
    # - Message validation and parsing
    # - Performance monitoring and statistics
    # - Pluggable message handlers
    #
    class MessageRouter
      include Ibkr::WebSocket::EventEmitter

      defines_events :message_routed, :routing_error, :unknown_message_type

      # Standard IBKR WebSocket message types
      MESSAGE_TYPES = {
        # Authentication
        "auth_response" => :handle_auth_response,

        # Connection management
        "ping" => :handle_ping,
        "pong" => :handle_pong,

        # Subscription management
        "subscription_response" => :handle_subscription_response,
        "subscription_error" => :handle_subscription_error,

        # Data streams
        "market_data" => :handle_market_data,
        "portfolio_update" => :handle_portfolio_update,
        "order_update" => :handle_order_update,
        "trade_data" => :handle_trade_data,
        "depth_data" => :handle_depth_data,

        # Authentication status
        "authenticated" => :handle_authentication_status,
        "status" => :handle_authentication_status,
        "account_info" => :handle_account_info,
        "account_summary" => :handle_account_summary_data,

        # System messages
        "system_message" => :handle_system_message,
        "error" => :handle_error_message,
        "rate_limit" => :handle_rate_limit_message
      }.freeze

      attr_reader :routing_statistics, :message_handlers

      # @param websocket_client [Ibkr::WebSocket::Client] Parent WebSocket client
      def initialize(websocket_client)
        @websocket_client = websocket_client
        @message_handlers = {}
        @routing_statistics = {
          total_messages: 0,
          by_type: Hash.new(0),
          routing_errors: 0,
          unknown_types: 0,
          processing_times: []
        }

        initialize_events
        setup_default_handlers
      end

      # Route incoming message to appropriate handler
      #
      # @param message [Hash] Parsed WebSocket message
      # @return [Boolean] True if message was routed successfully
      def route(message)
        start_time = Time.now
        @routing_statistics[:total_messages] += 1

        begin
          validate_message!(message)

          message_type = extract_message_type(message)
          @routing_statistics[:by_type][message_type] += 1

          handler = find_handler(message_type)

          if handler
            result = execute_handler(handler, message)
            record_routing_success(message_type, start_time)
            result
          else
            handle_unknown_message_type(message_type, message)
            false
          end
        rescue => e
          handle_routing_error(e, message, start_time)
          false
        end
      end

      # Register custom message handler
      #
      # @param message_type [String] Message type to handle
      # @param handler [Proc, Symbol] Handler proc or method name
      # @return [void]
      #
      # @example Register proc handler
      #   router.register_handler('custom_data') do |message|
      #     puts "Custom data: #{message}"
      #   end
      #
      # @example Register method handler
      #   router.register_handler('custom_data', :handle_custom_data)
      #
      def register_handler(message_type, handler = nil, &block)
        handler_proc = handler || block
        raise ArgumentError, "Handler is required" unless handler_proc

        @message_handlers[message_type] = handler_proc
      end

      # Unregister message handler
      #
      # @param message_type [String] Message type to unregister
      # @return [Boolean] True if handler was removed
      def unregister_handler(message_type)
        !!@message_handlers.delete(message_type)
      end

      # Get routing statistics
      #
      # @return [Hash] Current routing statistics
      def statistics
        stats = @routing_statistics.dup

        if stats[:processing_times].any?
          times = stats[:processing_times]
          stats[:average_processing_time] = times.sum / times.size
          stats[:max_processing_time] = times.max
          stats[:min_processing_time] = times.min
        end

        stats
      end

      # Reset routing statistics
      #
      # @return [void]
      def reset_statistics
        @routing_statistics = {
          total_messages: 0,
          by_type: Hash.new(0),
          routing_errors: 0,
          unknown_types: 0,
          processing_times: []
        }
      end

      private

      # Setup default message handlers
      def setup_default_handlers
        MESSAGE_TYPES.each do |message_type, method_name|
          @message_handlers[message_type] = method_name
        end
      end

      # Validate incoming message structure
      #
      # @param message [Hash] Message to validate
      # @raise [MessageProcessingError] If message is invalid
      def validate_message!(message)
        unless message.is_a?(Hash)
          raise MessageProcessingError.invalid_message_format(
            "Message must be a Hash, got #{message.class}"
          )
        end

        # Allow messages without 'type' field for IBKR system messages
        # These will be handled as 'system_message' type
        true
      end

      # Extract message type from message
      #
      # @param message [Hash] WebSocket message
      # @return [String] Message type
      def extract_message_type(message)
        # Handle subscription errors (messages with subscription_id and error) - prioritize over generic errors
        if (message.key?(:subscription_id) || message.key?("subscription_id")) &&
            (message.key?(:error) || message.key?("error"))
          return "subscription_error"
        end

        # Check for explicit type field
        type = message[:type] || message["type"]
        return type if type

        # Handle IBKR topic-based messages
        if message.key?(:topic) || message.key?("topic")
          topic = message[:topic] || message["topic"]
          case topic
          when "sts"
            return "status"
          when "system"
            return "system_message"
          when "act"
            return "account_info"
          when /^ssd\+/
            return "account_summary"
          else
            return "topic_#{topic}"
          end
        end

        # Handle IBKR system messages without type field
        if message.key?(:message) || message.key?("message")
          return "system_message"
        end

        # Default fallback
        "unknown"
      end

      # Find handler for message type
      #
      # @param message_type [String] Message type
      # @return [Proc, Symbol, nil] Handler or nil if not found
      def find_handler(message_type)
        @message_handlers[message_type]
      end

      # Execute message handler
      #
      # @param handler [Proc, Symbol] Handler to execute
      # @param message [Hash] Message to process
      # @return [Boolean] True if handled successfully
      def execute_handler(handler, message)
        case handler
        when Proc
          handler.call(message)
        when Symbol
          if respond_to?(handler, true)
            send(handler, message)
          else
            raise MessageProcessingError.message_routing_failed(
              "Handler method #{handler} not found"
            )
          end
        else
          raise MessageProcessingError.message_routing_failed(
            "Invalid handler type: #{handler.class}"
          )
        end

        true
      end

      # Handle unknown message type
      #
      # @param message_type [String] Unknown message type
      # @param message [Hash] Full message
      def handle_unknown_message_type(message_type, message)
        @routing_statistics[:unknown_types] += 1

        emit(:unknown_message_type,
          type: message_type,
          message: message)
      end

      # Handle routing error
      #
      # @param error [Exception] Error that occurred
      # @param message [Hash] Message being processed
      # @param start_time [Time] Processing start time
      def handle_routing_error(error, message, start_time)
        @routing_statistics[:routing_errors] += 1

        message_type = begin
          extract_message_type(message)
        rescue
          "unknown"
        end

        enhanced_error = MessageProcessingError.message_routing_failed(
          "Message routing failed: #{error.message}",
          context: {
            message_type: message_type,
            processing_time: Time.now - start_time,
            operation: "message_routing"
          },
          cause: error
        )

        emit(:routing_error, error: enhanced_error, message: message)
      end

      # Record successful routing
      #
      # @param message_type [String] Message type that was routed
      # @param start_time [Time] Processing start time
      def record_routing_success(message_type, start_time)
        processing_time = Time.now - start_time
        @routing_statistics[:processing_times] << processing_time

        # Keep only last N processing times for memory efficiency
        if @routing_statistics[:processing_times].size > Configuration::MAX_PROCESSING_TIMES
          @routing_statistics[:processing_times].shift(Configuration::PROCESSING_TIMES_CLEANUP_BATCH)
        end

        emit(:message_routed, type: message_type, processing_time: processing_time)
      end

      # Default message handlers

      def handle_auth_response(message)
        @websocket_client.connection_manager.handle_auth_response(message)
      end

      def handle_ping(message)
        # Respond with pong
        pong_message = {
          type: "pong",
          timestamp: message[:timestamp] || Time.now.to_f
        }
        @websocket_client.send_message(pong_message)
      end

      def handle_pong(message)
        @websocket_client.connection_manager.handle_pong_message(message)
      end

      def handle_subscription_response(message)
        @websocket_client.subscription_manager.handle_subscription_response(message)
      end

      def handle_subscription_error(message)
        @websocket_client.subscription_manager.handle_subscription_response(
          message.merge(status: "error")
        )
      end

      def handle_market_data(message)
        # Merge symbol and metadata with the data for complete market data event
        if message[:data] && message[:symbol]
          market_data = message[:data].merge(
            symbol: message[:symbol],
            subscription_id: message[:subscription_id],
            timestamp: message[:timestamp]
          )
          @websocket_client.emit(:market_data, market_data)
        else
          @websocket_client.emit(:market_data, message)
        end
      end

      def handle_portfolio_update(message)
        @websocket_client.emit(:portfolio_update, message[:data] || message)
      end

      def handle_order_update(message)
        # Merge order metadata with the data for complete order update event
        if message[:data]
          order_data = message[:data].merge(
            order_id: message[:order_id],
            account_id: message[:account_id],
            status: message[:status],
            timestamp: message[:timestamp]
          ).compact
          @websocket_client.emit(:order_update, order_data)
        else
          @websocket_client.emit(:order_update, message)
        end
      end

      def handle_trade_data(message)
        @websocket_client.emit(:trade_data, message[:data] || message)
      end

      def handle_depth_data(message)
        @websocket_client.emit(:depth_data, message[:data] || message)
      end

      def handle_system_message(message)
        # Handle specific IBKR system messages
        system_msg = message[:message] || message["message"]

        case system_msg
        when "waiting for session"
          # IBKR is waiting for the session to be ready
          # This is normal during connection establishment
          @websocket_client.emit(:session_pending, message)
        when "session ready", "authenticated"
          # Session is ready for use
          @websocket_client.emit(:session_ready, message)
        else
          # Generic system message
          @websocket_client.emit(:system_message, message)
        end
      end

      def handle_error_message(message)
        # Include error code in the message for better error identification
        error_msg = message[:message] || "Server error"
        if message[:error]
          error_msg = "#{message[:error]}: #{error_msg}"
        end

        error = MessageProcessingError.new(
          error_msg,
          context: {
            error_code: message[:code],
            error_type: message[:error],
            server_message: message
          }
        )
        @websocket_client.emit(:error, error)
      end

      def handle_rate_limit_message(message)
        @websocket_client.emit(:rate_limit, message)
      end

      def handle_authentication_status(message)
        # Handle IBKR authentication status messages (following Python implementation pattern)
        # IBKR sends status messages with topic "sts" and args containing authentication info
        args = message[:args] || message["args"] || message
        authenticated = args[:authenticated] || args["authenticated"]
        connected = args[:connected] || args["connected"]

        if authenticated == false
          @websocket_client.emit(:error, AuthenticationError.invalid_credentials(
            context: {
              message: message,
              operation: "websocket_authentication_status"
            }
          ))
        elsif authenticated == true && connected == true
          # Set the connection as authenticated
          @websocket_client.connection_manager.set_authenticated!
          @websocket_client.emit(:authenticated)
        else
          @websocket_client.emit(:system_message, message)
        end
      rescue
        @websocket_client.emit(:system_message, message)
      end

      def handle_account_info(message)
        # Handle IBKR account information messages
        @websocket_client.emit(:account_info, message)
      end

      def handle_account_summary_data(message)
        # Handle IBKR account summary data messages
        @websocket_client.emit(:account_summary, message)
      end
    end
  end
end
