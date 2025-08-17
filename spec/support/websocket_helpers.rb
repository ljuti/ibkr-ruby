# frozen_string_literal: true

require "faye/websocket"
require "eventmachine"

RSpec.shared_context "with mocked WebSocket connection" do
  let(:mock_websocket) do
    double("websocket",
      on: nil,
      send: nil,
      close: nil,
      ready_state: Faye::WebSocket::API::OPEN,
      url: "wss://api.ibkr.com/v1/api/ws")
  end

  let(:websocket_events) { {} }

  before do
    allow(Faye::WebSocket::Client).to receive(:new).and_return(mock_websocket)
    
    # Capture event handlers for simulation
    allow(mock_websocket).to receive(:on) do |event, &block|
      websocket_events[event] = block
    end
  end

  # Helper to simulate WebSocket events
  def simulate_websocket_event(event, *args)
    return unless websocket_events[event]
    websocket_events[event].call(*args)
  end

  # Helper to simulate incoming messages
  def simulate_websocket_message(data)
    message = double("message", data: data.to_json)
    simulate_websocket_event(:message, message)
  end

  # Helper to simulate connection events
  def simulate_websocket_open
    simulate_websocket_event(:open, double("event"))
  end

  def simulate_websocket_close(code = 1000, reason = "Normal closure")
    event = double("event", code: code, reason: reason)
    simulate_websocket_event(:close, event)
  end

  def simulate_websocket_error(message = "Connection error")
    error = double("error", message: message)
    simulate_websocket_event(:error, error)
  end
end

RSpec.shared_context "with WebSocket authentication" do
  include_context "with mocked WebSocket connection"
  include_context "with authenticated oauth client"

  let(:auth_message) do
    {
      type: "auth",
      token: valid_token.token,
      timestamp: Time.now.to_i
    }
  end

  let(:auth_success_response) do
    {
      type: "auth_response",
      status: "success",
      session_id: "ws_session_123",
      expires_at: (Time.now + 3600).to_i
    }
  end

  let(:auth_failure_response) do
    {
      type: "auth_response",
      status: "error",
      error: "invalid_token",
      message: "Authentication failed"
    }
  end
end

RSpec.shared_context "with WebSocket subscriptions" do
  include_context "with WebSocket authentication"

  let(:market_data_subscription) do
    {
      type: "subscribe",
      channel: "market_data",
      symbols: ["AAPL", "GOOGL"],
      fields: ["price", "volume", "bid", "ask"]
    }
  end

  let(:portfolio_subscription) do
    {
      type: "subscribe",
      channel: "portfolio",
      account_id: "DU123456"
    }
  end

  let(:order_subscription) do
    {
      type: "subscribe",
      channel: "orders",
      account_id: "DU123456"
    }
  end

  let(:subscription_success_response) do
    {
      type: "subscription_response",
      status: "success",
      subscription_id: "sub_123",
      channel: "market_data"
    }
  end

  let(:subscription_error_response) do
    {
      type: "subscription_response",
      status: "error",
      error: "invalid_symbol",
      message: "Symbol not found"
    }
  end
end

RSpec.shared_context "with real-time data streams" do
  include_context "with WebSocket subscriptions"

  let(:market_data_update) do
    {
      type: "market_data",
      subscription_id: "sub_123",
      symbol: "AAPL",
      timestamp: Time.now.to_f,
      data: {
        price: 150.25,
        volume: 1000,
        bid: 150.20,
        ask: 150.30,
        change: 2.15,
        change_percent: 1.45
      }
    }
  end

  let(:portfolio_update) do
    {
      type: "portfolio",
      account_id: "DU123456",
      timestamp: Time.now.to_f,
      data: {
        total_value: 125000.50,
        cash_balance: 25000.00,
        positions: [
          {
            symbol: "AAPL",
            quantity: 100,
            market_value: 15025.0,
            unrealized_pnl: 215.0
          }
        ]
      }
    }
  end

  let(:order_update) do
    {
      type: "order",
      account_id: "DU123456",
      order_id: "order_456",
      timestamp: Time.now.to_f,
      status: "filled",
      data: {
        symbol: "AAPL",
        side: "buy",
        quantity: 10,
        fill_price: 150.25,
        filled_quantity: 10,
        remaining_quantity: 0
      }
    }
  end
end

RSpec.shared_context "with WebSocket error scenarios" do
  include_context "with mocked WebSocket connection"

  let(:rate_limit_error) do
    {
      type: "error",
      error: "rate_limit_exceeded",
      message: "Too many requests",
      retry_after: 60
    }
  end

  let(:invalid_message_error) do
    {
      type: "error",
      error: "invalid_message",
      message: "Malformed JSON",
      received_data: "invalid json {"
    }
  end

  let(:subscription_limit_error) do
    {
      type: "error",
      error: "subscription_limit",
      message: "Maximum subscriptions reached",
      limit: 100
    }
  end
end

RSpec.shared_context "with WebSocket performance monitoring" do
  around(:each, :performance) do |example|
    start_time = Time.now
    start_memory = GC.stat[:heap_live_slots]
    
    example.run
    
    end_time = Time.now
    end_memory = GC.stat[:heap_live_slots]
    
    duration = end_time - start_time
    memory_delta = end_memory - start_memory
    
    if duration > 0.5
      puts "⚠️  Slow WebSocket test: #{example.metadata[:full_description]} (#{duration.round(2)}s)"
    end
    
    if memory_delta > 10000
      puts "⚠️  High memory usage: #{example.metadata[:full_description]} (+#{memory_delta} slots)"
    end
  end
end

# Mock EventMachine for testing without actual event loop
RSpec.shared_context "with mocked EventMachine" do
  before do
    # Mock EventMachine.run to execute block immediately
    allow(EventMachine).to receive(:run) do |&block|
      block.call if block
    end
    
    # Mock EventMachine.stop
    allow(EventMachine).to receive(:stop)
    
    # Mock EventMachine.next_tick to execute immediately
    allow(EventMachine).to receive(:next_tick) do |&block|
      block.call if block
    end
    
    # Mock EventMachine timers
    allow(EventMachine).to receive(:add_timer) do |delay, &block|
      # For testing, execute timer callbacks immediately
      block.call if block
      double("timer", cancel: nil)
    end
    
    allow(EventMachine).to receive(:add_periodic_timer) do |interval, &block|
      double("periodic_timer", cancel: nil)
    end
  end
end