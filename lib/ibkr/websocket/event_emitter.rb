# frozen_string_literal: true

module Ibkr
  module WebSocket
    # Event emitter module providing event handling capabilities for WebSocket components
    #
    # Provides a simple observer pattern implementation for handling WebSocket events
    # like connection state changes, message reception, and error conditions.
    #
    # @example Including in a class
    #   class MyWebSocketClient
    #     include Ibkr::WebSocket::EventEmitter
    #     
    #     def initialize
    #       initialize_events
    #     end
    #     
    #     def process_message(data)
    #       emit(:message_received, data)
    #     end
    #   end
    #
    # @example Using events
    #   client = MyWebSocketClient.new
    #   client.on(:message_received) { |data| puts "Got: #{data}" }
    #   client.process_message("hello")  # Prints: "Got: hello"
    #
    module EventEmitter
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Define the event types this class can emit
        #
        # @param event_names [Array<Symbol>] List of event names
        # @return [void]
        def defines_events(*event_names)
          event_types.concat(event_names)
        end

        # Get all defined event types for this class
        #
        # @return [Array<Symbol>] List of event names
        def event_types
          @event_types ||= []
        end
      end

      # Initialize the event handling system
      # Call this in your class's initialize method
      #
      # @return [void]
      def initialize_events
        @event_handlers = Hash.new { |h, k| h[k] = [] }
        @event_stats = Hash.new { |h, k| h[k] = { emitted: 0, handlers: 0 } }
      end

      # Register an event handler for a specific event type
      #
      # @param event [Symbol] The event type to listen for
      # @param block [Proc] The handler block to execute when event is emitted
      # @return [self] Returns self for method chaining
      #
      # @example
      #   websocket.on(:connected) { puts "WebSocket connected!" }
      #   websocket.on(:market_data) { |data| process_market_data(data) }
      #
      def on(event, &block)
        raise ArgumentError, "Block required for event handler" unless block

        @event_handlers[event] << block
        @event_stats[event][:handlers] = @event_handlers[event].size
        self
      end

      # Remove an event handler for a specific event type
      #
      # @param event [Symbol] The event type
      # @param block [Proc] The specific handler block to remove (optional)
      # @return [self] Returns self for method chaining
      #
      def off(event, &block)
        if block
          @event_handlers[event].delete(block)
        else
          @event_handlers[event].clear
        end
        @event_stats[event][:handlers] = @event_handlers[event].size
        self
      end

      # Remove all event handlers for all events
      #
      # @return [self] Returns self for method chaining
      def remove_all_listeners
        @event_handlers.clear
        @event_stats.clear
        self
      end

      # Emit an event to all registered handlers
      #
      # @param event [Symbol] The event type to emit
      # @param args [Array] Arguments to pass to the event handlers
      # @return [Integer] Number of handlers that were called
      #
      # @example
      #   emit(:connected)
      #   emit(:market_data, { symbol: "AAPL", price: 150.25 })
      #   emit(:error, error_object, "Additional context")
      #
      def emit(event, *args)
        handlers = @event_handlers[event]
        return 0 if handlers.empty?

        @event_stats[event][:emitted] += 1
        successful_calls = 0

        handlers.each do |handler|
          begin
            handler.call(*args)
            successful_calls += 1
          rescue => e
            handle_event_error(event, e, handler, *args)
          end
        end

        successful_calls
      end

      # Check if there are any handlers registered for an event
      #
      # @param event [Symbol] The event type to check
      # @return [Boolean] True if handlers are registered
      def has_listeners?(event)
        @event_handlers[event].any?
      end

      # Get count of handlers for a specific event
      #
      # @param event [Symbol] The event type
      # @return [Integer] Number of registered handlers
      def listener_count(event)
        @event_handlers[event].size
      end

      # Get statistics about event usage
      #
      # @return [Hash] Statistics hash with event names as keys
      def event_statistics
        @event_stats.dup
      end

      private

      # Handle errors that occur during event handler execution
      #
      # @param event [Symbol] The event that was being handled
      # @param error [Exception] The error that occurred
      # @param handler [Proc] The handler that failed
      # @param args [Array] Arguments that were passed to the handler
      def handle_event_error(event, error, handler, *args)
        enhanced_error = create_event_error(event, error, handler, args)
        
        # Try to emit error event, but don't create infinite recursion
        if event != :error && has_listeners?(:error)
          emit(:error, enhanced_error)
        else
          # Fallback: log the error or raise it
          warn "Event handler error in #{self.class}##{event}: #{error.message}"
          warn error.backtrace.join("\n") if error.backtrace
        end
      end

      # Create an enhanced error object for event handler failures
      #
      # @param event [Symbol] The event that was being handled
      # @param error [Exception] The original error
      # @param handler [Proc] The handler that failed
      # @param args [Array] Arguments passed to the handler
      # @return [Exception] Enhanced error object
      def create_event_error(event, error, handler, args)
        context = {
          event: event,
          handler_count: @event_handlers[event].size,
          args_count: args.size,
          operation: "event_handler_execution"
        }

        if defined?(Ibkr::WebSocket::EventError)
          Ibkr::WebSocket::EventError.handler_failed(
            "Event handler failed: #{error.message}",
            context: context,
            cause: error
          )
        else
          # Fallback if error classes aren't loaded yet
          StandardError.new("Event handler failed for #{event}: #{error.message}")
        end
      end
    end
  end
end