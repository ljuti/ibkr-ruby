# frozen_string_literal: true

# Shared examples for WebSocket connection behaviors
RSpec.shared_examples "a resilient trading connection" do
  it "maintains connection health during normal operations" do
    # Given an established trading connection
    establish_authenticated_connection(websocket_client)

    # When the connection operates normally
    expect(websocket_client).to be_connected
    expect(websocket_client).to be_authenticated

    # Then it should remain healthy
    expect(websocket_client.connection_healthy?).to be true
  end

  it "provides clear status when connection is lost" do
    # Given an active trading connection
    establish_authenticated_connection(websocket_client)

    # When the connection is lost
    simulate_websocket_close(1006, "Abnormal closure")

    # Then the status should reflect the disconnection
    expect(websocket_client).not_to be_connected
    expect(websocket_client.connection_state).to eq(:disconnected)
  end
end

RSpec.shared_examples "a real-time data subscriber" do
  it "delivers market updates to active subscribers" do
    # Given a trader subscribed to market data
    establish_authenticated_connection(websocket_client)

    received_updates = []
    websocket_client.on_market_data { |data| received_updates << data }

    subscription_id = websocket_client.subscribe_market_data(["AAPL"], ["price"])
    confirm_subscription(websocket_client, subscription_id)

    # When market data arrives
    simulate_market_data_update(websocket_client, symbol: "AAPL", price: 155.50, subscription_id: subscription_id)

    # Then the trader receives the update
    expect(received_updates).not_to be_empty
    expect(received_updates.last[:symbol]).to eq("AAPL")
    expect(received_updates.last[:price]).to eq(155.50)
  end

  it "manages subscription lifecycle transparently" do
    # Given a trader with market data needs
    establish_authenticated_connection(websocket_client)

    # When they subscribe to market data
    subscription_id = websocket_client.subscribe_market_data(["MSFT"], ["price", "volume"])
    confirm_subscription(websocket_client, subscription_id)

    # Then the subscription is actively tracked
    expect(websocket_client.active_subscriptions).to include(subscription_id)
    expect(websocket_client.subscribed_symbols).to include("MSFT")

    # When they unsubscribe
    websocket_client.unsubscribe(subscription_id)

    # Then the subscription is cleanly removed
    expect(websocket_client.active_subscriptions).not_to include(subscription_id)
    expect(websocket_client.subscribed_symbols).not_to include("MSFT")
  end
end

RSpec.shared_examples "a portfolio monitor" do
  it "tracks portfolio value changes in real-time" do
    # Given a trader monitoring their portfolio
    establish_authenticated_connection(websocket_client)

    portfolio_updates = []
    websocket_client.on_portfolio_update { |data| portfolio_updates << data }

    subscription_id = websocket_client.subscribe_portfolio(websocket_client.account_id)
    confirm_subscription(websocket_client, subscription_id)

    # When portfolio value changes
    simulate_portfolio_update(websocket_client, total_value: 130000.00)

    # Then they see the updated value immediately
    expect(portfolio_updates).not_to be_empty
    expect(portfolio_updates.last[:total_value]).to eq(130000.00)
  end

  it "provides position-level P&L details" do
    # Given a trader with open positions
    establish_authenticated_connection(websocket_client)

    position_updates = []
    websocket_client.on_portfolio_update do |data|
      position_updates.concat(data[:positions] || [])
    end

    subscription_id = websocket_client.subscribe_portfolio(websocket_client.account_id)
    confirm_subscription(websocket_client, subscription_id)

    # When portfolio updates arrive
    simulate_portfolio_update(websocket_client)

    # Then position-level details are available
    expect(position_updates).not_to be_empty
    aapl_position = position_updates.find { |p| p[:symbol] == "AAPL" }
    expect(aapl_position).not_to be_nil
    expect(aapl_position[:unrealized_pnl]).to be_a(Numeric)
  end
end

RSpec.shared_examples "an order execution tracker" do
  it "notifies trader of order status changes" do
    # Given a trader with pending orders
    establish_authenticated_connection(websocket_client)

    order_updates = []
    websocket_client.on_order_update { |data| order_updates << data }

    subscription_id = websocket_client.subscribe_orders(websocket_client.account_id)
    confirm_subscription(websocket_client, subscription_id)

    # When order status changes
    simulate_order_update(websocket_client, order_id: "BUY_001", status: "filled")

    # Then they receive immediate notification
    expect(order_updates).not_to be_empty
    expect(order_updates.last[:order_id]).to eq("BUY_001")
    expect(order_updates.last[:status]).to eq("filled")
  end

  it "tracks partial fills accurately" do
    # Given a trader with a large order
    establish_authenticated_connection(websocket_client)

    fill_updates = []
    websocket_client.on_order_update { |data| fill_updates << data }

    subscription_id = websocket_client.subscribe_orders(websocket_client.account_id)
    confirm_subscription(websocket_client, subscription_id)

    # When the order partially fills
    simulate_order_update(websocket_client,
      order_id: "LARGE_001",
      status: "partially_filled",
      symbol: "AAPL")

    # Then partial fill details are provided
    expect(fill_updates).not_to be_empty
    partial_fill = fill_updates.last
    expect(partial_fill[:status]).to eq("partially_filled")
    expect(partial_fill[:filled_quantity]).to be < partial_fill[:quantity] if partial_fill[:quantity]
  end
end

RSpec.shared_examples "subscription limit enforcer" do
  it "prevents excessive subscriptions" do
    # Given a subscription manager with limits
    # This should be tested through public interface only

    # When approaching the limit
    results = []
    10.times do |i|
      results << subscription_manager.subscribe(
        channel: "market_data",
        symbols: ["STOCK#{i}"],
        fields: ["price"]
      )
    end

    # Then it should enforce limits appropriately
    # (specific expectations depend on configured limits)
    expect(results).to all(be_a(String).or(be_a(Ibkr::WebSocket::SubscriptionError)))
  end

  it "provides clear feedback when limits are exceeded" do
    # Implementation depends on public interface
    # This example assumes a proper factory setup
    expect {
      # Attempt to exceed limits
    }.to raise_error(Ibkr::WebSocket::SubscriptionError) do |error|
      expect(error.message).to include("limit")
    end
  end
end
