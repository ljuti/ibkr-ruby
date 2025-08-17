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
    it_behaves_like "a real-time data subscriber"

    context "when trader monitors stock prices" do
      it "delivers real-time price updates for subscribed symbols", :websocket_performance do
        # Given a trader wants to monitor Apple stock prices in real-time
        expect(websocket_client).to be_instance_of(Ibkr::WebSocket::Client)
        expect(websocket_client.connected?).to be false

        # When they establish connection and subscribe to market data
        establish_authenticated_connection(websocket_client)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price", "volume"])
        confirm_subscription(websocket_client, subscription_id)

        # Then they receive real-time market updates
        received_updates = []
        websocket_client.on_market_data { |data| received_updates << data }

        simulate_market_data_update(websocket_client, symbol: "AAPL", price: 150.25, subscription_id: subscription_id)

        expect(received_updates).not_to be_empty
        expect(received_updates.first[:symbol]).to eq("AAPL")
        expect(received_updates.first[:price]).to eq(150.25)
        expect(received_updates.first[:volume]).to eq(1000)
      end

      it "manages multiple symbol subscriptions for portfolio monitoring" do
        # Given a trader wants to monitor their diversified portfolio
        symbols = ["AAPL", "GOOGL", "MSFT", "TSLA"]

        # When they subscribe to multiple symbols for comprehensive tracking
        establish_authenticated_connection(websocket_client)

        subscription_ids = symbols.map do |symbol|
          websocket_client.subscribe_market_data([symbol], ["price"])
        end

        # Confirm all subscriptions
        subscription_ids.each do |subscription_id|
          confirm_subscription(websocket_client, subscription_id)
        end

        # Then all symbols are actively monitored
        expect(websocket_client.active_subscriptions.size).to eq(symbols.size)
        expect(websocket_client.subscribed_symbols).to match_array(symbols)
      end

      it "provides clear feedback when subscription requests fail" do
        # Given a trader attempts to subscribe to an invalid symbol
        establish_authenticated_connection(websocket_client)

        # When they request data for a non-existent symbol
        subscription_id = websocket_client.subscribe_market_data(["INVALID"], ["price"])

        error_response = subscription_error_response.merge(
          subscription_id: subscription_id,
          error: "invalid_symbol"
        )
        simulate_websocket_message(error_response)

        # Then they receive clear feedback about the invalid request
        expect(websocket_client.subscription_errors).to include(subscription_id)
        error = websocket_client.last_subscription_error(subscription_id)
        expect(error[:error]).to eq("invalid_symbol")
      end
    end

    context "when trader manages their data streams" do
      it "allows selective unsubscription from market data feeds" do
        # Given a trader has active market data subscriptions
        establish_authenticated_connection(websocket_client)

        subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
        confirm_subscription(websocket_client, subscription_id)

        expect(websocket_client.active_subscriptions).to include(subscription_id)

        # When they decide to stop monitoring a specific symbol
        websocket_client.unsubscribe(subscription_id)

        # Then that symbol is no longer tracked
        expect(websocket_client.active_subscriptions).not_to include(subscription_id)
        expect(websocket_client.subscribed_symbols).not_to include("AAPL")
      end

      it "maintains clean state when disconnecting from trading session" do
        # Given a trader has multiple active subscriptions
        establish_authenticated_connection(websocket_client)

        create_active_subscriptions(websocket_client, [
          {type: :market_data, symbols: ["AAPL"]},
          {type: :market_data, symbols: ["GOOGL"]}
        ])

        expect(websocket_client.active_subscriptions.size).to eq(2)

        # When they end their trading session
        websocket_client.disconnect

        # Then all subscription state is properly cleaned up
        expect(websocket_client.active_subscriptions).to be_empty
        expect(websocket_client.subscribed_symbols).to be_empty
      end
    end
  end

  describe "Real-time portfolio monitoring" do
    it_behaves_like "a portfolio monitor"

    context "when trader tracks portfolio performance" do
      it "delivers real-time portfolio value changes" do
        # Given a trader wants to track their portfolio performance
        establish_authenticated_connection(websocket_client)

        # When they subscribe to portfolio updates
        subscription_id = websocket_client.subscribe_portfolio("DU123456")
        confirm_subscription(websocket_client, subscription_id)

        # Then they receive immediate portfolio value updates
        received_updates = []
        websocket_client.on_portfolio_update { |data| received_updates << data }

        simulate_portfolio_update(websocket_client, total_value: 125000.50)

        expect(received_updates).not_to be_empty
        portfolio_data = received_updates.first
        expect(portfolio_data[:total_value]).to eq(125000.50)
        expect(portfolio_data[:positions]).to be_an(Array)
        expect(portfolio_data[:positions].first[:symbol]).to eq("AAPL")
      end

      it "tracks position-level profit and loss in real-time" do
        # Given a trader has open positions with fluctuating values
        establish_authenticated_connection(websocket_client)

        subscription_id = websocket_client.subscribe_portfolio("DU123456")
        confirm_subscription(websocket_client, subscription_id)

        # When market movements affect their positions
        pnl_updates = []
        websocket_client.on_portfolio_update do |data|
          data[:positions].each do |position|
            pnl_updates << {
              symbol: position[:symbol],
              unrealized_pnl: position[:unrealized_pnl]
            }
          end
        end

        simulate_portfolio_update(websocket_client)

        # Then P&L changes are immediately reflected
        expect(pnl_updates).not_to be_empty
        aapl_pnl = pnl_updates.find { |p| p[:symbol] == "AAPL" }
        expect(aapl_pnl[:unrealized_pnl]).to eq(215.0)
      end
    end
  end

  describe "Real-time order management" do
    it_behaves_like "an order execution tracker"

    context "when trader tracks order execution" do
      it "provides immediate notification of order execution" do
        # Given a trader has submitted orders to the market
        establish_authenticated_connection(websocket_client)

        # When they monitor order status changes
        subscription_id = websocket_client.subscribe_orders("DU123456")
        confirm_subscription(websocket_client, subscription_id)

        order_updates = []
        websocket_client.on_order_update { |data| order_updates << data }

        # Then they receive immediate execution notifications
        simulate_order_update(websocket_client, order_id: "order_456", status: "filled")

        expect(order_updates).not_to be_empty
        order_data = order_updates.first
        expect(order_data[:order_id]).to eq("order_456")
        expect(order_data[:status]).to eq("filled")
        expect(order_data[:symbol]).to eq("AAPL")
        expect(order_data[:fill_price]).to eq(150.25)
      end

      it "tracks partial execution progress for large orders" do
        # Given a trader has submitted large orders that may execute incrementally
        establish_authenticated_connection(websocket_client)

        # When they monitor order progress
        subscription_id = websocket_client.subscribe_orders("DU123456")
        confirm_subscription(websocket_client, subscription_id)

        partial_fill_updates = []
        websocket_client.on_order_update { |data| partial_fill_updates << data }

        # Then they receive detailed partial fill information
        simulate_order_update(websocket_client,
          order_id: "large_order_123",
          status: "partially_filled",
          symbol: "AAPL")

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

        [
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

        websocket_client.subscribe_market_data(["AAPL"], ["price"])

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

        websocket_client.subscribe_market_data(["AAPL"], ["price"])

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
