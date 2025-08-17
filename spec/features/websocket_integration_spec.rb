# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Interactive Brokers WebSocket Integration", type: :feature, websocket_integration: true do
  include_context "with WebSocket test environment"
  include_context "with real-time data streams"

  let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }
  let(:websocket_client) { client.websocket }

  describe "End-to-end WebSocket workflow" do
    context "when user wants real-time market monitoring" do
      it "successfully establishes complete streaming workflow", websocket_performance: true do
        # Given a user wants to monitor their portfolio and Apple stock in real-time
        portfolio_updates = []
        market_updates = []
        order_updates = []

        # When they establish WebSocket connection and authenticate
        websocket_client.connect
        expect(websocket_client.connection_state).to eq(:connecting)

        # Connection opens
        simulate_websocket_open
        expect(websocket_client.connection_state).to eq(:connected)

        # Authentication succeeds
        simulate_websocket_message(auth_success_response)
        expect(websocket_client.authenticated?).to be true

        # When they subscribe to multiple data streams
        market_subscription = websocket_client.subscribe_market_data(["AAPL"], ["price", "volume", "bid", "ask"])
        portfolio_subscription = websocket_client.subscribe_portfolio("DU123456")
        order_subscription = websocket_client.subscribe_orders("DU123456")

        # Set up event handlers
        websocket_client.on_market_data { |data| market_updates << data }
        websocket_client.on_portfolio_update { |data| portfolio_updates << data }
        websocket_client.on_order_update { |data| order_updates << data }

        # Confirm subscriptions
        simulate_websocket_message(subscription_success_response.merge(subscription_id: market_subscription))
        simulate_websocket_message(subscription_success_response.merge(subscription_id: portfolio_subscription, channel: "portfolio"))
        simulate_websocket_message(subscription_success_response.merge(subscription_id: order_subscription, channel: "orders"))

        # Then they should receive real-time updates across all streams
        simulate_websocket_message(market_data_update.merge(subscription_id: market_subscription))
        simulate_websocket_message(portfolio_update)
        simulate_websocket_message(order_update)

        # Verify all data streams are working
        expect(market_updates).not_to be_empty
        expect(portfolio_updates).not_to be_empty
        expect(order_updates).not_to be_empty

        # Verify data integrity
        expect(market_updates.first[:symbol]).to eq("AAPL")
        expect(market_updates.first[:price]).to eq(150.25)
        expect(portfolio_updates.first[:total_value]).to eq(125000.50)
        expect(order_updates.first[:status]).to eq("filled")

        # Verify subscription management
        expect(websocket_client.active_subscriptions.size).to eq(3)
        expect(websocket_client.subscribed_symbols).to include("AAPL")
      end

      it "handles complete workflow with connection interruption and recovery" do
        # Given established streaming workflow
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        market_subscription = websocket_client.subscribe_market_data(["AAPL", "GOOGL"], ["price"])
        portfolio_subscription = websocket_client.subscribe_portfolio("DU123456")
        
        simulate_websocket_message(subscription_success_response.merge(subscription_id: market_subscription))
        simulate_websocket_message(subscription_success_response.merge(subscription_id: portfolio_subscription, channel: "portfolio"))

        original_subscriptions = websocket_client.active_subscriptions.dup
        expect(original_subscriptions.size).to eq(2)

        # When connection is unexpectedly lost
        simulate_websocket_close(1006, "Connection lost")
        expect(websocket_client.connected?).to be false
        expect(websocket_client.authenticated?).to be false

        # Then automatic reconnection should occur
        expect(websocket_client.reconnecting?).to be true

        # Simulate successful reconnection
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # Then subscriptions should be automatically restored
        expect(websocket_client.active_subscriptions.size).to eq(2)
        expect(websocket_client.subscribed_symbols).to match_array(["AAPL", "GOOGL"])

        # And data flow should resume
        received_updates = []
        websocket_client.on_market_data { |data| received_updates << data }

        simulate_websocket_message(market_data_update.merge(subscription_id: market_subscription))
        expect(received_updates).not_to be_empty
      end

      it "manages subscription lifecycle with live portfolio tracking" do
        # Given authenticated WebSocket connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        portfolio_values = []
        position_changes = []

        # When subscribing to portfolio updates
        portfolio_subscription = websocket_client.subscribe_portfolio("DU123456")
        simulate_websocket_message(subscription_success_response.merge(subscription_id: portfolio_subscription, channel: "portfolio"))

        websocket_client.on_portfolio_update do |data|
          portfolio_values << data[:total_value]
          data[:positions].each { |pos| position_changes << pos if pos[:symbol] == "AAPL" }
        end

        # Then portfolio changes should be tracked over time
        # Initial portfolio state
        simulate_websocket_message(portfolio_update)

        # Market movement affecting portfolio
        updated_portfolio = portfolio_update.dup
        updated_portfolio[:data][:total_value] = 126500.75
        updated_portfolio[:data][:positions][0][:market_value] = 16525.0
        updated_portfolio[:data][:positions][0][:unrealized_pnl] = 1715.0
        simulate_websocket_message(updated_portfolio)

        # Verify portfolio tracking
        expect(portfolio_values).to eq([125000.50, 126500.75])
        expect(position_changes.size).to eq(2)
        expect(position_changes.last[:unrealized_pnl]).to eq(1715.0)

        # When unsubscribing from portfolio updates
        websocket_client.unsubscribe(portfolio_subscription)
        expect(websocket_client.active_subscriptions).not_to include(portfolio_subscription)

        # Then no further updates should be received
        portfolio_values.clear
        simulate_websocket_message(portfolio_update)
        expect(portfolio_values).to be_empty
      end
    end

    context "when handling high-frequency trading scenarios" do
      it "processes rapid market data updates efficiently", websocket_performance: true do
        # Given high-frequency market data scenario
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price", "volume"])
        simulate_websocket_message(subscription_success_response.merge(subscription_id: subscription_id))

        updates_received = []
        processing_times = []

        websocket_client.on_market_data do |data|
          start_time = Time.now
          updates_received << data
          processing_times << Time.now - start_time
        end

        # When receiving rapid updates (simulating high-frequency trading)
        start_time = Time.now
        
        100.times do |i|
          update = market_data_update.dup
          update[:data][:price] = 150.0 + (i * 0.01)
          update[:data][:volume] = 1000 + (i * 10)
          update[:timestamp] = (Time.now.to_f * 1000).to_i + i  # Millisecond precision
          simulate_websocket_message(update.merge(subscription_id: subscription_id))
        end

        end_time = Time.now
        total_time = end_time - start_time

        # Then all updates should be processed efficiently
        expect(updates_received.size).to eq(100)
        expect(total_time).to be < 1.0  # Process 100 updates in under 1 second

        # Verify data integrity under load
        prices = updates_received.map { |u| u[:price] }
        expect(prices.first).to eq(150.0)
        expect(prices.last).to eq(150.99)
        expect(prices).to eq(prices.sort)  # Should be in order

        # Verify processing efficiency
        avg_processing_time = processing_times.sum / processing_times.size
        expect(avg_processing_time).to be < 0.001  # Under 1ms per message
      end

      it "handles burst order updates during active trading" do
        # Given active order monitoring
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        order_subscription = websocket_client.subscribe_orders("DU123456")
        simulate_websocket_message(subscription_success_response.merge(subscription_id: order_subscription, channel: "orders"))

        order_events = []
        websocket_client.on_order_update { |data| order_events << data }

        # When burst of order events occurs
        order_statuses = %w[submitted working partially_filled filled]
        order_id = "order_123"

        order_statuses.each_with_index do |status, i|
          order_event = order_update.dup
          order_event[:order_id] = order_id
          order_event[:status] = status
          order_event[:filled_quantity] = [0, 0, 25, 50][i]
          order_event[:remaining_quantity] = 50 - [0, 0, 25, 50][i]
          order_event[:timestamp] = Time.now.to_f + (i * 0.1)
          
          simulate_websocket_message(order_event)
        end

        # Then order lifecycle should be tracked correctly
        expect(order_events.size).to eq(4)
        
        statuses = order_events.map { |e| e[:status] }
        expect(statuses).to eq(%w[submitted working partially_filled filled])
        
        filled_quantities = order_events.map { |e| e[:filled_quantity] }
        expect(filled_quantities).to eq([0, 0, 25, 50])
      end
    end

    context "when handling error scenarios and recovery" do
      it "gracefully handles and recovers from various error conditions" do
        # Given established connection with subscriptions
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        simulate_websocket_message(subscription_success_response.merge(subscription_id: subscription_id))

        # When various error conditions occur
        
        # 1. Rate limiting error
        simulate_websocket_message(rate_limit_error)
        expect(websocket_client.rate_limited?).to be true
        expect(websocket_client.rate_limit_retry_after).to eq(60)

        # 2. Invalid message error
        simulate_websocket_message(invalid_message_error)
        expect(websocket_client.message_errors.size).to eq(1)

        # 3. Authentication expiration
        auth_expired = { type: "auth_expired", message: "Token expired" }
        simulate_websocket_message(auth_expired)
        expect(websocket_client.authenticated?).to be false

        # 4. Connection error and recovery
        simulate_websocket_error("Network error")
        expect(websocket_client.connection_state).to eq(:error)

        # Recovery process
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # Then system should recover gracefully
        expect(websocket_client.connected?).to be true
        expect(websocket_client.authenticated?).to be true
        
        # Subscriptions should be restored
        expect(websocket_client.active_subscriptions).to include(subscription_id)
      end

      it "implements circuit breaker pattern for persistent failures" do
        # Given WebSocket client with circuit breaker
        websocket_client.connect
        simulate_websocket_open

        # When repeated authentication failures occur
        5.times do
          simulate_websocket_message(auth_failure_response)
        end

        # Then circuit breaker should activate
        expect(websocket_client.circuit_breaker_open?).to be true
        expect(websocket_client.auth_rate_limited?).to be true

        # When attempting immediate reconnection
        expect {
          websocket_client.reauthenticate
        }.to raise_error(Ibkr::WebSocket::CircuitBreakerError)

        # When circuit breaker timeout expires
        allow(Time).to receive(:now).and_return(Time.now + 300)  # 5 minutes later
        expect(websocket_client.circuit_breaker_open?).to be false

        # Then normal operation should resume
        expect { websocket_client.reauthenticate }.not_to raise_error
      end
    end

    context "when testing with live-like conditions", websocket_integration: true do
      it "maintains stable connection over extended period" do
        # Given long-running WebSocket connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        simulate_websocket_message(subscription_success_response.merge(subscription_id: subscription_id))

        # When simulating extended operation with periodic updates
        total_updates = 0
        heartbeat_count = 0

        websocket_client.on_market_data { |_| total_updates += 1 }
        websocket_client.on_heartbeat { |_| heartbeat_count += 1 }

        # Simulate 1 hour of operation (compressed time)
        60.times do |minute|
          # Market data updates (every 10 seconds = 6 per minute)
          6.times do |second|
            update = market_data_update.dup
            update[:data][:price] = 150.0 + (minute * 0.1) + (second * 0.01)
            update[:timestamp] = Time.now.to_f + (minute * 60) + (second * 10)
            simulate_websocket_message(update.merge(subscription_id: subscription_id))
          end

          # Heartbeat every minute
          pong = { type: "pong", timestamp: Time.now.to_f + (minute * 60) }
          simulate_websocket_message(pong)
        end

        # Then connection should remain stable
        expect(websocket_client.connected?).to be true
        expect(websocket_client.authenticated?).to be true
        expect(total_updates).to eq(360)  # 60 minutes * 6 updates per minute
        expect(heartbeat_count).to eq(60)  # 1 per minute
        expect(websocket_client.connection_healthy?).to be true
      end
    end
  end

  describe "WebSocket performance benchmarking" do
    context "when measuring WebSocket performance", websocket_performance: true do
      it "benchmarks message processing throughput" do
        # Given authenticated WebSocket with market data subscription
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        
        messages_processed = 0
        websocket_client.on_market_data { |_| messages_processed += 1 }

        # When processing high volume of messages
        message_count = 10000
        start_time = Time.now

        message_count.times do |i|
          update = market_data_update.dup
          update[:data][:price] = 150.0 + (i * 0.0001)
          simulate_websocket_message(update.merge(subscription_id: subscription_id))
        end

        end_time = Time.now
        processing_time = end_time - start_time

        # Then throughput should meet performance requirements
        messages_per_second = message_count / processing_time
        expect(messages_per_second).to be > 1000  # At least 1000 messages per second
        expect(messages_processed).to eq(message_count)

        puts "WebSocket Throughput: #{messages_per_second.round} messages/second"
      end

      it "measures memory efficiency under sustained load" do
        # Given WebSocket client under sustained load
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])

        start_memory = GC.stat[:heap_live_slots]

        # When processing sustained message load
        5000.times do |i|
          update = market_data_update.dup
          update[:data][:price] = 150.0 + (i * 0.0001)
          update[:data][:volume] = 1000 + i
          update[:timestamp] = Time.now.to_f + (i * 0.001)
          simulate_websocket_message(update.merge(subscription_id: subscription_id))

          # Force garbage collection periodically
          GC.start if i % 1000 == 0
        end

        end_memory = GC.stat[:heap_live_slots]
        memory_growth = end_memory - start_memory

        # Then memory usage should remain stable
        expect(memory_growth).to be < 100000  # Less than 100k new objects
        puts "Memory growth: #{memory_growth} objects"
      end
    end
  end
end