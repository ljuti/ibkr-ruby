# frozen_string_literal: true

module WebSocketTestFactories
  # Factory for creating configured WebSocket clients
  def build_websocket_client(account_id: "DU123456", authenticated: false, live: false)
    client = Ibkr::Client.new(default_account_id: account_id, live: live)
    allow(client).to receive(:oauth_client).and_return(oauth_client) if defined?(oauth_client)
    allow(client).to receive(:authenticated?).and_return(authenticated)

    websocket = client.websocket
    if authenticated
      websocket.connect
      simulate_websocket_open
      simulate_websocket_message(auth_status_message)
    end

    websocket
  end

  # Factory for creating subscription manager with configuration
  def build_subscription_manager(
    websocket_client: nil,
    max_total: 100,
    max_market_data: 50,
    max_portfolio: 5,
    max_orders: 10,
    rate_limit: 60
  )
    client = websocket_client || double("websocket_client",
      send_message: true,
      authenticated?: true,
      emit: true,
      account_id: "DU123456")

    manager = Ibkr::WebSocket::SubscriptionManager.new(client)

    # Use a configuration method if available, otherwise fall back to test doubles
    if manager.respond_to?(:configure_for_testing)
      manager.configure_for_testing(
        limits: {
          total: max_total,
          market_data: max_market_data,
          portfolio: max_portfolio,
          orders: max_orders
        },
        rate_limit: rate_limit
      )
    else
      # For now, we'll use stubs to avoid internal state manipulation
      allow(manager).to receive(:max_subscriptions).and_return(max_total)
      allow(manager).to receive(:max_subscriptions_per_channel).and_return({
        market_data: max_market_data,
        portfolio: max_portfolio,
        orders: max_orders
      })
      allow(manager).to receive(:subscription_rate_limit).and_return(rate_limit)
    end

    manager
  end

  # Helper to simulate subscription confirmation through public interface
  def confirm_subscription(websocket_client, subscription_id, status: "success")
    simulate_websocket_message({
      type: "subscription_response",
      subscription_id: subscription_id,
      status: status,
      message: (status == "success") ? "Subscription confirmed" : "Subscription failed"
    })
  end

  # Helper to simulate market data updates
  def simulate_market_data_update(websocket_client, symbol: "AAPL", price: 150.25, subscription_id: nil)
    message = {
      type: "market_data",
      symbol: symbol,
      subscription_id: subscription_id || "sub_#{SecureRandom.hex(4)}",
      timestamp: Time.now.to_f,
      data: {
        price: price,
        volume: 1000,
        bid: price - 0.05,
        ask: price + 0.05
      }
    }
    simulate_websocket_message(message)
  end

  # Helper to simulate order updates
  def simulate_order_update(websocket_client, order_id: "order_123", status: "filled", symbol: "AAPL")
    message = {
      type: "order_update",
      order_id: order_id,
      account_id: websocket_client.account_id,
      status: status,
      timestamp: Time.now.to_f,
      data: {
        symbol: symbol,
        side: "buy",
        quantity: 10,
        fill_price: 150.25,
        filled_quantity: (status == "filled") ? 10 : 5,
        remaining_quantity: (status == "filled") ? 0 : 5
      }
    }
    simulate_websocket_message(message)
  end

  # Helper to simulate portfolio updates
  def simulate_portfolio_update(websocket_client, total_value: 125000.50)
    message = {
      type: "portfolio_update",
      account_id: websocket_client.account_id,
      timestamp: Time.now.to_f,
      data: {
        total_value: total_value,
        cash_balance: 25000.00,
        positions: [
          {symbol: "AAPL", quantity: 100, value: 15025.00, unrealized_pnl: 215.00},
          {symbol: "GOOGL", quantity: 50, value: 60000.00, unrealized_pnl: -125.00}
        ]
      }
    }
    simulate_websocket_message(message)
  end

  # Helper to establish authenticated connection
  def establish_authenticated_connection(websocket_client)
    websocket_client.connect
    simulate_websocket_open
    simulate_websocket_message(auth_status_message)
    websocket_client
  end

  # Helper to create active subscriptions
  def create_active_subscriptions(websocket_client, subscriptions = [])
    subscription_ids = []

    subscriptions.each do |sub|
      case sub[:type]
      when :market_data
        id = websocket_client.subscribe_market_data(sub[:symbols], sub[:fields] || ["price"])
      when :portfolio
        id = websocket_client.subscribe_portfolio(sub[:account_id] || websocket_client.account_id)
      when :orders
        id = websocket_client.subscribe_orders(sub[:account_id] || websocket_client.account_id)
      else
        raise ArgumentError, "Unknown subscription type: #{sub[:type]}"
      end

      subscription_ids << id
      confirm_subscription(websocket_client, id)
    end

    subscription_ids
  end

  # Helper to simulate rate limit scenario
  def simulate_rate_limit_error(websocket_client, subscription_id, retry_after: 60)
    message = {
      type: "error",
      subscription_id: subscription_id,
      status: "error",
      error: "rate_limit_exceeded",
      message: "Too many requests",
      retry_after: retry_after
    }
    simulate_websocket_message(message)
  end

  # Helper to wait for async operations
  def wait_for_subscription_confirmation(websocket_client, subscription_id, timeout: 5)
    Timeout.timeout(timeout) do
      loop do
        break if websocket_client.active_subscriptions.include?(subscription_id)
        sleep 0.1
      end
    end
  rescue Timeout::Error
    raise "Subscription #{subscription_id} was not confirmed within #{timeout} seconds"
  end
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include WebSocketTestFactories, type: :feature
  config.include WebSocketTestFactories, websocket: true
end
