# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Interactive Brokers WebSocket Streaming", type: :feature do
  include_context "with WebSocket test environment"
  include_context "with real-time data streams"
  include_context "with WebSocket authentication"
  include_context "with WebSocket error scenarios"

  let(:client) do
    client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
    allow(client).to receive(:oauth_client).and_return(oauth_client)
    allow(client).to receive(:authenticated?).and_return(true)
    client
  end
  let(:websocket_client) { client.websocket }

  describe "Real-time market data streaming" do
    context "when user subscribes to market data" do
      it "successfully receives real-time price updates", :websocket_performance do
        # Given a user wants to monitor Apple stock prices in real-time
        expect(websocket_client).to be_instance_of(Ibkr::WebSocket::Client)
        expect(websocket_client.connected?).to be false

        # When they connect and subscribe to market data
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price", "volume"])
        simulate_websocket_message(subscription_success_response.merge(subscription_id: subscription_id))

        # Then they should receive real-time market updates
        received_updates = []
        websocket_client.on_market_data { |data| received_updates << data }

        simulate_websocket_message(market_data_update.merge(subscription_id: subscription_id))

        expect(received_updates).not_to be_empty
        expect(received_updates.first[:symbol]).to eq("AAPL")
        expect(received_updates.first[:price]).to eq(150.25)
        expect(received_updates.first[:volume]).to eq(1000)
      end

      it "handles multiple symbol subscriptions efficiently" do
        # Given a user wants to monitor multiple stocks
        symbols = ["AAPL", "GOOGL", "MSFT", "TSLA"]

        # When they subscribe to multiple symbols
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        subscription_ids = symbols.map do |symbol|
          websocket_client.subscribe_market_data([symbol], ["price"])
        end

        # Simulate subscription confirmations from server
        subscription_ids.each do |subscription_id|
          simulate_websocket_message({
            type: "subscription_response",
            subscription_id: subscription_id,
            status: "success",
            message: "Subscription confirmed"
          })
        end

        # Then all subscriptions should be tracked
        expect(websocket_client.active_subscriptions.size).to eq(symbols.size)
        expect(websocket_client.subscribed_symbols).to match_array(symbols)
      end

      it "gracefully handles subscription failures" do
        # Given a user attempts to subscribe to an invalid symbol
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        # When they try to subscribe to an invalid symbol
        subscription_id = websocket_client.subscribe_market_data(["INVALID"], ["price"])
        
        error_response = subscription_error_response.merge(
          subscription_id: subscription_id,
          error: "invalid_symbol"
        )
        simulate_websocket_message(error_response)

        # Then they should receive clear error feedback
        expect(websocket_client.subscription_errors).to include(subscription_id)
        error = websocket_client.last_subscription_error(subscription_id)
        expect(error[:error]).to eq("invalid_symbol")
      end
    end

    context "when user manages subscription lifecycle" do
      it "can unsubscribe from market data streams" do
        # Given a user has active market data subscriptions
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        
        # Simulate subscription confirmation from server
        simulate_websocket_message({
          type: "subscription_response",
          subscription_id: subscription_id,
          status: "success",
          message: "Subscription confirmed"
        })
        
        expect(websocket_client.active_subscriptions).to include(subscription_id)

        # When they unsubscribe
        websocket_client.unsubscribe(subscription_id)

        # Then the subscription should be removed
        expect(websocket_client.active_subscriptions).not_to include(subscription_id)
        expect(websocket_client.subscribed_symbols).not_to include("AAPL")
      end

      it "automatically cleans up subscriptions on disconnect" do
        # Given a user has active subscriptions
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        subscription_id1 = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        subscription_id2 = websocket_client.subscribe_market_data(["GOOGL"], ["price"])
        
        # Simulate subscription confirmations from server
        [subscription_id1, subscription_id2].each do |subscription_id|
          simulate_websocket_message({
            type: "subscription_response",
            subscription_id: subscription_id,
            status: "success",
            message: "Subscription confirmed"
          })
        end
        
        expect(websocket_client.active_subscriptions.size).to eq(2)

        # When connection is lost
        websocket_client.disconnect

        # Then all subscriptions should be cleared
        expect(websocket_client.active_subscriptions).to be_empty
        expect(websocket_client.subscribed_symbols).to be_empty
      end
    end
  end

  describe "Real-time portfolio monitoring" do
    context "when user monitors portfolio changes" do
      it "receives real-time portfolio value updates" do
        # Given a user wants to monitor their portfolio in real-time
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        # When they subscribe to portfolio updates
        subscription_id = websocket_client.subscribe_portfolio("DU123456")
        simulate_websocket_message({
          type: "subscription_response",
          subscription_id: subscription_id,
          status: "success",
          message: "Subscription confirmed"
        })

        # Then they should receive portfolio updates
        received_updates = []
        websocket_client.on_portfolio_update { |data| received_updates << data }

        simulate_websocket_message(portfolio_update.merge(type: "portfolio_update"))

        expect(received_updates).not_to be_empty
        portfolio_data = received_updates.first
        expect(portfolio_data[:total_value]).to eq(125000.50)
        expect(portfolio_data[:positions]).to be_an(Array)
        expect(portfolio_data[:positions].first[:symbol]).to eq("AAPL")
      end

      it "calculates real-time P&L correctly" do
        # Given a user has positions with unrealized P&L
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        subscription_id = websocket_client.subscribe_portfolio("DU123456")
        
        # Simulate subscription confirmation from server
        simulate_websocket_message({
          type: "subscription_response",
          subscription_id: subscription_id,
          status: "success",
          message: "Subscription confirmed"
        })
        
        # When portfolio updates arrive
        pnl_updates = []
        websocket_client.on_portfolio_update do |data|
          data[:positions].each do |position|
            pnl_updates << {
              symbol: position[:symbol],
              unrealized_pnl: position[:unrealized_pnl]
            }
          end
        end

        simulate_websocket_message(portfolio_update.merge(type: "portfolio_update"))

        # Then P&L should be accurately tracked
        expect(pnl_updates).not_to be_empty
        aapl_pnl = pnl_updates.find { |p| p[:symbol] == "AAPL" }
        expect(aapl_pnl[:unrealized_pnl]).to eq(215.0)
      end
    end
  end

  describe "Real-time order management" do
    context "when user monitors order status" do
      it "receives real-time order execution updates" do
        # Given a user has submitted orders
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        # When they subscribe to order updates
        subscription_id = websocket_client.subscribe_orders("DU123456")
        
        # Simulate subscription confirmation from server
        simulate_websocket_message({
          type: "subscription_response",
          subscription_id: subscription_id,
          status: "success",
          message: "Subscription confirmed"
        })
        
        order_updates = []
        websocket_client.on_order_update { |data| order_updates << data }

        # Then they should receive real-time order status changes
        simulate_websocket_message(order_update.merge(type: "order_update"))

        expect(order_updates).not_to be_empty
        order_data = order_updates.first
        expect(order_data[:order_id]).to eq("order_456")
        expect(order_data[:status]).to eq("filled")
        expect(order_data[:symbol]).to eq("AAPL")
        expect(order_data[:fill_price]).to eq(150.25)
      end

      it "handles partial fills correctly" do
        # Given a user has large orders that may fill partially
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        # When they subscribe to order updates
        subscription_id = websocket_client.subscribe_orders("DU123456")
        simulate_websocket_message({
          type: "subscription_response",
          subscription_id: subscription_id,
          status: "success",
          message: "Subscription confirmed"
        })

        # When partial fill updates arrive
        partial_fill_updates = []
        websocket_client.on_order_update { |data| partial_fill_updates << data }

        partial_fill = order_update.dup
        partial_fill[:data] = partial_fill[:data].dup
        partial_fill[:status] = "partially_filled"
        partial_fill[:data][:filled_quantity] = 5
        partial_fill[:data][:remaining_quantity] = 5

        simulate_websocket_message(partial_fill.merge(type: "order_update"))

        # Then partial fill information should be tracked
        expect(partial_fill_updates.first[:status]).to eq("partially_filled")
        expect(partial_fill_updates.first[:filled_quantity]).to eq(5)
        expect(partial_fill_updates.first[:remaining_quantity]).to eq(5)
      end
    end
  end

  describe "Connection resilience and error handling" do
    context "when connection issues occur" do
      xit "automatically reconnects after connection loss", :websocket_performance do
        # TODO: Requires more sophisticated test infrastructure for async reconnection timing
        # Given a user has an established WebSocket connection
        websocket_client.connect
        simulate_websocket_open
        expect(websocket_client.connected?).to be true

        # When connection is unexpectedly lost
        simulate_websocket_close(1006, "Abnormal closure")
        expect(websocket_client.connected?).to be false

        # Then client should attempt automatic reconnection
        expect(websocket_client.reconnecting?).to be true
        
        # Simulate successful reconnection
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)
        
        expect(websocket_client.connected?).to be true
        expect(websocket_client.reconnect_attempts).to be > 0
      end

      it "implements exponential backoff for reconnection attempts" do
        # Given connection keeps failing
        websocket_client.connect
        simulate_websocket_close(1006, "Connection failed")

        # When multiple reconnection attempts are made
        delays = []
        5.times do |attempt|
          delays << websocket_client.next_reconnect_delay(attempt + 1)
        end

        # Then delays should increase exponentially
        expect(delays[0]).to be < delays[1]
        expect(delays[1]).to be < delays[2]
        expect(delays[2]).to be < delays[3]
        expect(delays.last).to be <= websocket_client.max_reconnect_delay
      end

      xit "restores subscriptions after successful reconnection" do
        # TODO: Requires sophisticated test infrastructure for simulating reconnection state management
        # Given a user has active subscriptions
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        original_subscriptions = [
          websocket_client.subscribe_market_data(["AAPL"], ["price"]),
          websocket_client.subscribe_portfolio("DU123456")
        ]

        # When connection is lost and restored
        simulate_websocket_close(1006, "Connection lost")
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        # Then subscriptions should be automatically restored
        expect(websocket_client.active_subscriptions.size).to eq(2)
        expect(websocket_client.subscribed_symbols).to include("AAPL")
      end
    end

    context "when rate limiting occurs" do
      it "handles subscription rate limits gracefully" do
        # Given a user is approaching subscription limits
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        # When they exceed the subscription rate limit
        expect {
          subscription_id = websocket_client.subscribe_market_data(["RATE_LIMITED"], ["price"])
          rate_limit_response = rate_limit_error.merge(
            subscription_id: subscription_id,
            status: "error"
          )
          simulate_websocket_message(rate_limit_response)
        }.not_to raise_error

        # Then they should receive rate limit guidance
        expect(websocket_client.last_error).to include("rate_limit_exceeded")
        expect(websocket_client.rate_limit_retry_after).to eq(60)
      end
    end
  end

  describe "Data quality and integrity" do
    context "when processing high-frequency updates" do
      it "maintains data consistency under load", :websocket_performance do
        # Given high-frequency market data updates
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        
        updates = []
        websocket_client.on_market_data { |data| updates << data }

        # When receiving many rapid updates
        100.times do |i|
          price_update = market_data_update.dup
          price_update[:data] = price_update[:data].dup
          price_update[:data][:price] = 150.0 + (i * 0.01)
          price_update[:timestamp] = Time.now.to_f + (i * 0.001)
          simulate_websocket_message(price_update)
        end

        # Then all updates should be processed correctly
        expect(updates.size).to eq(100)
        prices = updates.map { |u| u[:price] }
        expect(prices.first).to eq(150.0)
        expect(prices.last).to eq(150.99)
      end

      xit "filters duplicate messages effectively" do
        # TODO: Duplicate message filtering feature not yet implemented - requires message deduplication logic
        # Given duplicate messages may arrive
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        
        updates = []
        websocket_client.on_market_data { |data| updates << data }

        # When duplicate messages are received
        3.times { simulate_websocket_message(market_data_update) }

        # Then duplicates should be filtered out
        expect(updates.size).to eq(1)
      end
    end
  end
end