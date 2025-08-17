# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::WebSocket::EventEmitter do
  # Create a test class that includes the EventEmitter module
  let(:test_class) do
    Class.new do
      include Ibkr::WebSocket::EventEmitter

      def initialize
        initialize_events
      end
    end
  end

  let(:emitter) { test_class.new }

  describe "module inclusion and class methods" do
    context "when module is included in a class" do
      it "extends the class with ClassMethods" do
        expect(test_class).to respond_to(:defines_events)
        expect(test_class).to respond_to(:event_types)
      end

      it "provides defines_events method for declaring event types" do
        test_class.defines_events(:connected, :disconnected, :error)

        expect(test_class.event_types).to include(:connected, :disconnected, :error)
      end

      it "accumulates event types across multiple defines_events calls" do
        test_class.defines_events(:connection_events)
        test_class.defines_events(:data_events, :error_events)

        expect(test_class.event_types).to include(:connection_events, :data_events, :error_events)
      end

      it "maintains separate event types for different classes" do
        other_class = Class.new do
          include Ibkr::WebSocket::EventEmitter
        end

        test_class.defines_events(:class_a_event)
        other_class.defines_events(:class_b_event)

        expect(test_class.event_types).to include(:class_a_event)
        expect(test_class.event_types).not_to include(:class_b_event)
        expect(other_class.event_types).to include(:class_b_event)
        expect(other_class.event_types).not_to include(:class_a_event)
      end
    end
  end

  describe "#initialize_events" do
    it "initializes event handlers hash with default empty arrays" do
      emitter = test_class.new

      handlers = emitter.instance_variable_get(:@event_handlers)
      expect(handlers).to be_a(Hash)
      expect(handlers[:nonexistent_event]).to eq([])
    end

    it "initializes event statistics hash with default counters" do
      emitter = test_class.new

      stats = emitter.instance_variable_get(:@event_stats)
      expect(stats).to be_a(Hash)
      expect(stats[:nonexistent_event]).to eq({emitted: 0, handlers: 0})
    end
  end

  describe "#on (event registration)" do
    context "when registering event handlers" do
      it "registers handler block for specified event" do
        handler_called = false
        emitter.on(:test_event) { handler_called = true }

        emitter.emit(:test_event)

        expect(handler_called).to be true
      end

      it "supports multiple handlers for the same event" do
        call_order = []
        emitter.on(:test_event) { call_order << :first }
        emitter.on(:test_event) { call_order << :second }

        emitter.emit(:test_event)

        expect(call_order).to eq([:first, :second])
      end

      it "returns self for method chaining" do
        result = emitter.on(:test_event) {}

        expect(result).to eq(emitter)
      end

      it "updates handler count statistics" do
        emitter.on(:test_event) {}
        emitter.on(:test_event) {}

        stats = emitter.event_statistics
        expect(stats[:test_event][:handlers]).to eq(2)
      end

      it "supports handlers with parameters" do
        received_data = nil
        emitter.on(:data_event) { |data| received_data = data }

        emitter.emit(:data_event, "test_data")

        expect(received_data).to eq("test_data")
      end

      it "supports handlers with multiple parameters" do
        received_params = []
        emitter.on(:multi_param_event) { |a, b, c| received_params = [a, b, c] }

        emitter.emit(:multi_param_event, 1, 2, 3)

        expect(received_params).to eq([1, 2, 3])
      end
    end

    context "when handler registration fails" do
      it "raises ArgumentError when no block is provided" do
        expect {
          emitter.on(:test_event)
        }.to raise_error(ArgumentError, "Block required for event handler")
      end
    end
  end

  describe "#off (event deregistration)" do
    context "when removing specific handlers" do
      it "removes specific handler block when provided" do
        handler1 = proc { "handler1" }
        handler2 = proc { "handler2" }

        emitter.on(:test_event, &handler1)
        emitter.on(:test_event, &handler2)

        emitter.off(:test_event, &handler1)

        expect(emitter.listener_count(:test_event)).to eq(1)
      end

      it "updates handler count statistics after removal" do
        emitter.on(:test_event) {}
        emitter.on(:test_event) {}
        emitter.off(:test_event)

        stats = emitter.event_statistics
        expect(stats[:test_event][:handlers]).to eq(0)
      end

      it "returns self for method chaining" do
        emitter.on(:test_event) {}
        result = emitter.off(:test_event)

        expect(result).to eq(emitter)
      end
    end

    context "when removing all handlers for an event" do
      it "clears all handlers when no specific block provided" do
        emitter.on(:test_event) {}
        emitter.on(:test_event) {}
        emitter.on(:other_event) {}

        emitter.off(:test_event)

        expect(emitter.listener_count(:test_event)).to eq(0)
        expect(emitter.listener_count(:other_event)).to eq(1)
      end
    end

    context "when removing handlers that don't exist" do
      it "handles removal of non-existent handlers gracefully" do
        non_existent_handler = proc {}

        expect {
          emitter.off(:test_event, &non_existent_handler)
        }.not_to raise_error

        expect(emitter.listener_count(:test_event)).to eq(0)
      end
    end
  end

  describe "#remove_all_listeners" do
    context "when clearing all event handlers" do
      it "removes all handlers for all events" do
        emitter.on(:event1) {}
        emitter.on(:event2) {}
        emitter.on(:event3) {}

        emitter.remove_all_listeners

        expect(emitter.listener_count(:event1)).to eq(0)
        expect(emitter.listener_count(:event2)).to eq(0)
        expect(emitter.listener_count(:event3)).to eq(0)
      end

      it "clears event statistics" do
        emitter.on(:test_event) {}
        emitter.emit(:test_event)

        emitter.remove_all_listeners

        stats = emitter.event_statistics
        expect(stats).to be_empty
      end

      it "returns self for method chaining" do
        result = emitter.remove_all_listeners

        expect(result).to eq(emitter)
      end
    end
  end

  describe "#emit (event emission)" do
    context "when emitting events to registered handlers" do
      it "calls all registered handlers for the event" do
        call_count = 0
        emitter.on(:test_event) { call_count += 1 }
        emitter.on(:test_event) { call_count += 1 }

        emitter.emit(:test_event)

        expect(call_count).to eq(2)
      end

      it "returns count of handlers that were successfully called" do
        emitter.on(:test_event) {}
        emitter.on(:test_event) {}

        result = emitter.emit(:test_event)

        expect(result).to eq(2)
      end

      it "passes arguments to event handlers" do
        received_args = []
        emitter.on(:test_event) { |*args| received_args = args }

        emitter.emit(:test_event, "arg1", "arg2", {key: "value"})

        expect(received_args).to eq(["arg1", "arg2", {key: "value"}])
      end

      it "updates emission statistics" do
        emitter.on(:test_event) {}
        emitter.emit(:test_event)
        emitter.emit(:test_event)

        stats = emitter.event_statistics
        expect(stats[:test_event][:emitted]).to eq(2)
      end

      it "returns 0 when no handlers are registered" do
        result = emitter.emit(:nonexistent_event)

        expect(result).to eq(0)
      end
    end

    context "when handlers raise exceptions" do
      it "handles handler exceptions gracefully and continues with other handlers" do
        call_order = []
        emitter.on(:test_event) { call_order << :first }
        emitter.on(:test_event) { raise "Handler error" }
        emitter.on(:test_event) { call_order << :third }

        # Mock the error handling to prevent actual warnings
        allow(emitter).to receive(:handle_event_error)

        result = emitter.emit(:test_event)

        expect(call_order).to eq([:first, :third])
        expect(result).to eq(2) # Two successful calls
      end

      it "calls handle_event_error for each failed handler" do
        double("error_handler")
        allow(emitter).to receive(:handle_event_error)

        emitter.on(:test_event) { raise StandardError, "Test error" }
        emitter.emit(:test_event)

        expect(emitter).to have_received(:handle_event_error).with(
          :test_event,
          an_instance_of(StandardError),
          anything
        )
      end
    end

    context "when emitting events with complex data" do
      it "handles nested data structures correctly" do
        received_data = nil
        complex_data = {
          user: {id: 123, name: "John"},
          actions: ["login", "view_page"],
          metadata: {timestamp: Time.now}
        }

        emitter.on(:complex_event) { |data| received_data = data }
        emitter.emit(:complex_event, complex_data)

        expect(received_data).to eq(complex_data)
        expect(received_data[:user][:name]).to eq("John")
      end
    end
  end

  describe "#has_listeners?" do
    context "when checking for event listeners" do
      it "returns true when handlers are registered for event" do
        emitter.on(:test_event) {}

        expect(emitter.has_listeners?(:test_event)).to be true
      end

      it "returns false when no handlers are registered for event" do
        expect(emitter.has_listeners?(:nonexistent_event)).to be false
      end

      it "returns false after all handlers are removed" do
        emitter.on(:test_event) {}
        emitter.off(:test_event)

        expect(emitter.has_listeners?(:test_event)).to be false
      end
    end
  end

  describe "#listener_count" do
    context "when counting event listeners" do
      it "returns correct count of registered handlers" do
        emitter.on(:test_event) {}
        emitter.on(:test_event) {}
        emitter.on(:other_event) {}

        expect(emitter.listener_count(:test_event)).to eq(2)
        expect(emitter.listener_count(:other_event)).to eq(1)
      end

      it "returns 0 for events with no handlers" do
        expect(emitter.listener_count(:nonexistent_event)).to eq(0)
      end

      it "updates count correctly after handlers are removed" do
        emitter.on(:test_event) {}
        emitter.on(:test_event) {}
        emitter.off(:test_event)

        expect(emitter.listener_count(:test_event)).to eq(0)
      end
    end
  end

  describe "#event_statistics" do
    context "when retrieving event usage statistics" do
      it "returns hash with emission and handler counts" do
        emitter.on(:test_event) {}
        emitter.on(:test_event) {}
        emitter.emit(:test_event)

        stats = emitter.event_statistics

        expect(stats[:test_event]).to include(
          emitted: 1,
          handlers: 2
        )
      end

      it "returns statistics hash" do
        emitter.on(:test_event) {}
        emitter.emit(:test_event)

        stats = emitter.event_statistics

        # Should return current statistics
        expect(stats[:test_event][:emitted]).to eq(1)
        expect(stats[:test_event][:handlers]).to eq(1)
      end

      it "includes statistics for all events that have been used" do
        emitter.on(:event1) {}
        emitter.on(:event2) {}
        emitter.emit(:event1)

        stats = emitter.event_statistics

        expect(stats).to have_key(:event1)
        expect(stats).to have_key(:event2)
      end
    end
  end

  describe "error handling behavior" do
    describe "#handle_event_error" do
      context "when handling event handler errors" do
        let(:test_error) { StandardError.new("Test error") }
        let(:test_handler) { proc { raise test_error } }

        it "creates enhanced error object with context information" do
          allow(emitter).to receive(:create_event_error).and_return(test_error)
          allow(emitter).to receive(:has_listeners?).with(:error).and_return(false)
          allow(emitter).to receive(:warn)

          emitter.send(:handle_event_error, :test_event, test_error, test_handler, "arg1", "arg2")

          expect(emitter).to have_received(:create_event_error).with(
            :test_event,
            test_error,
            test_handler,
            ["arg1", "arg2"]
          )
        end

        it "emits error event when error listeners are available" do
          enhanced_error = double("enhanced_error")
          allow(emitter).to receive(:create_event_error).and_return(enhanced_error)
          allow(emitter).to receive(:has_listeners?).with(:error).and_return(true)
          allow(emitter).to receive(:emit)

          emitter.send(:handle_event_error, :test_event, test_error, test_handler)

          expect(emitter).to have_received(:emit).with(:error, enhanced_error)
        end

        it "prevents infinite recursion when error event itself fails" do
          allow(emitter).to receive(:create_event_error).and_return(test_error)
          allow(emitter).to receive(:has_listeners?).with(:error).and_return(false)
          allow(emitter).to receive(:warn)
          allow(test_error).to receive(:backtrace).and_return(["line1", "line2"])

          # Should not attempt to emit error event for error event
          emitter.send(:handle_event_error, :error, test_error, test_handler)

          expect(emitter).to have_received(:warn).twice # Warning and backtrace
        end

        it "falls back to warning when no error listeners available" do
          allow(emitter).to receive(:create_event_error).and_return(test_error)
          allow(emitter).to receive(:has_listeners?).with(:error).and_return(false)
          allow(emitter).to receive(:warn)

          emitter.send(:handle_event_error, :test_event, test_error, test_handler)

          expect(emitter).to have_received(:warn).with(/Event handler error.*test_event.*Test error/)
        end
      end
    end

    describe "#create_event_error" do
      let(:test_error) { StandardError.new("Original error") }
      let(:test_handler) { proc {} }

      context "when creating enhanced error objects" do
        it "creates enhanced error with context information" do
          # Stub the WebSocket error classes for testing
          stub_const("Ibkr::WebSocket::EventError", Class.new(StandardError) do
            def self.handler_failed(message, context:, cause:)
              new("#{message} - Context: #{context}")
            end
          end)

          result = emitter.send(:create_event_error, :test_event, test_error, test_handler, ["arg1"])

          expect(result).to be_a(Ibkr::WebSocket::EventError)
          expect(result.message).to include("handler failed")
          expect(result.message).to include("test_event")
        end

        it "handles errors with context through public interface" do
          error_received = nil

          # Register an error handler to capture the enhanced error
          emitter.on(:error) { |err| error_received = err }

          # Register a failing handler
          emitter.on(:test_event) { raise StandardError, "Original error" }

          # Trigger the event, which should fail and emit an error event
          emitter.emit(:test_event)

          # Verify error was captured with context
          expect(error_received).to be_a(StandardError)
          expect(error_received.message).to include("Original error")
        end

        it "provides fallback error when WebSocket error classes unavailable" do
          # Hide the WebSocket error classes
          hide_const("Ibkr::WebSocket::EventError") if defined?(Ibkr::WebSocket::EventError)

          result = emitter.send(:create_event_error, :test_event, test_error, test_handler, [])

          expect(result).to be_a(StandardError)
          expect(result.message).to include("Event handler failed for test_event")
          expect(result.message).to include("Original error")
        end
      end
    end
  end

  describe "real-world usage scenarios" do
    context "when implementing WebSocket connection events" do
      let(:websocket_emitter) do
        Class.new do
          include Ibkr::WebSocket::EventEmitter

          defines_events :connected, :disconnected, :message_received, :error

          def initialize
            initialize_events
          end

          def simulate_connection
            emit(:connected, {timestamp: Time.now})
          end

          def simulate_message(data)
            emit(:message_received, data)
          end

          def simulate_error(error)
            emit(:error, error)
          end

          def simulate_disconnection(reason = nil)
            emit(:disconnected, {reason: reason, timestamp: Time.now})
          end
        end.new
      end

      it "handles connection lifecycle events correctly" do
        connection_events = []

        websocket_emitter.on(:connected) { |data| connection_events << [:connected, data] }
        websocket_emitter.on(:disconnected) { |data| connection_events << [:disconnected, data] }

        websocket_emitter.simulate_connection
        websocket_emitter.simulate_disconnection("user_initiated")

        expect(connection_events.size).to eq(2)
        expect(connection_events[0][0]).to eq(:connected)
        expect(connection_events[1][0]).to eq(:disconnected)
        expect(connection_events[1][1][:reason]).to eq("user_initiated")
      end

      it "processes message events with data transformation" do
        received_messages = []

        websocket_emitter.on(:message_received) do |data|
          processed_data = data.is_a?(String) ? JSON.parse(data) : data
          received_messages << processed_data
        end

        websocket_emitter.simulate_message('{"type": "market_data", "symbol": "AAPL"}')
        websocket_emitter.simulate_message({type: "heartbeat", timestamp: Time.now})

        expect(received_messages.size).to eq(2)
        expect(received_messages[0]["type"]).to eq("market_data")
        expect(received_messages[1][:type]).to eq("heartbeat")
      end
    end

    context "when implementing market data event processing" do
      let(:market_data_processor) do
        Class.new do
          include Ibkr::WebSocket::EventEmitter

          defines_events :price_update, :volume_update, :trade_executed

          def initialize
            initialize_events
            @price_cache = {}
          end

          def process_market_update(symbol, price, volume)
            old_price = @price_cache[symbol]
            @price_cache[symbol] = price

            emit(:price_update, {
              symbol: symbol,
              price: price,
              previous_price: old_price,
              change: old_price ? price - old_price : 0
            })

            emit(:volume_update, {
              symbol: symbol,
              volume: volume,
              timestamp: Time.now
            })
          end

          def process_trade(symbol, quantity, price)
            emit(:trade_executed, {
              symbol: symbol,
              quantity: quantity,
              price: price,
              timestamp: Time.now
            })
          end
        end.new
      end

      it "processes market data updates with price change calculation" do
        price_updates = []

        market_data_processor.on(:price_update) do |data|
          price_updates << data
        end

        market_data_processor.process_market_update("AAPL", 150.00, 1000)
        market_data_processor.process_market_update("AAPL", 151.50, 1200)

        expect(price_updates.size).to eq(2)
        expect(price_updates[0][:change]).to eq(0) # First update, no previous price
        expect(price_updates[1][:change]).to eq(1.50) # Second update shows change
      end

      it "handles multiple simultaneous event types" do
        all_events = []

        [:price_update, :volume_update, :trade_executed].each do |event_type|
          market_data_processor.on(event_type) do |data|
            all_events << [event_type, data]
          end
        end

        market_data_processor.process_market_update("GOOGL", 2800.00, 500)
        market_data_processor.process_trade("GOOGL", 100, 2801.00)

        expect(all_events.size).to eq(3) # price_update, volume_update, trade_executed
        expect(all_events.map(&:first)).to include(:price_update, :volume_update, :trade_executed)
      end
    end
  end

  describe "performance and memory considerations" do
    context "when handling large numbers of events and handlers" do
      it "efficiently manages many handlers for the same event" do
        handler_calls = 0

        1000.times do
          emitter.on(:bulk_event) { handler_calls += 1 }
        end

        start_time = Time.now
        emitter.emit(:bulk_event)
        end_time = Time.now

        expect(handler_calls).to eq(1000)
        expect(end_time - start_time).to be < 1.0 # Should complete quickly
      end

      it "maintains performance with many different event types" do
        (1..1000).each do |i|
          emitter.on(:"event_#{i}") {}
        end

        start_time = Time.now
        (1..1000).each do |i|
          emitter.emit(:"event_#{i}")
        end
        end_time = Time.now

        expect(end_time - start_time).to be < 2.0 # Should scale reasonably
      end
    end

    context "when managing memory usage" do
      it "allows garbage collection of removed handlers" do
        large_object = "x" * 10000

        emitter.on(:test_event) { large_object.length }

        # Remove the handler
        emitter.off(:test_event)
        large_object = nil

        # Force garbage collection
        GC.start

        expect(emitter.listener_count(:test_event)).to eq(0)
      end
    end
  end

  describe "thread safety considerations" do
    context "when used in multi-threaded environments" do
      it "handles concurrent event emissions safely" do
        call_counts = Hash.new(0)
        mutex = Mutex.new

        emitter.on(:concurrent_event) do |thread_id|
          mutex.synchronize { call_counts[thread_id] += 1 }
        end

        threads = (1..10).map do |i|
          Thread.new do
            10.times { emitter.emit(:concurrent_event, i) }
          end
        end

        threads.each(&:join)

        total_calls = call_counts.values.sum
        expect(total_calls).to eq(100) # 10 threads * 10 calls each
      end

      it "handles concurrent handler registration and emission" do
        results = []
        results_mutex = Mutex.new

        # Thread that continuously emits events
        emitter_thread = Thread.new do
          100.times do |i|
            emitter.emit(:dynamic_event, i)
            sleep(0.001)
          end
        end

        # Thread that adds handlers dynamically
        handler_thread = Thread.new do
          10.times do |i|
            emitter.on(:dynamic_event) do |data|
              results_mutex.synchronize { results << [i, data] }
            end
            sleep(0.01)
          end
        end

        emitter_thread.join
        handler_thread.join

        expect(results).not_to be_empty
        expect(results.all? { |handler_id, data| data.is_a?(Integer) }).to be true
      end
    end
  end
end
