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
    # Ensure mock_websocket is reset for each test
    allow(mock_websocket).to receive(:ready_state).and_return(Faye::WebSocket::API::OPEN)

    allow(Faye::WebSocket::Client).to receive(:new) do |url, protocols, options|
      # Reset event handlers for each new WebSocket
      websocket_events.clear
      mock_websocket
    end

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

  # Mock the tickle response that provides session token
  let(:mock_session_token) { "cb0f2f5202aab5d3ca020c118356f315" }
  let(:tickle_response) do
    {
      "session" => mock_session_token,
      "hmds" => {"error" => "no bridge"},
      "iserver" => {
        "authStatus" => {
          "authenticated" => true,
          "competing" => false,
          "connected" => true,
          "message" => "",
          "MAC" => "06:4C:4B:38:D4:CE",
          "serverInfo" => {
            "serverName" => "JifZ27010",
            "serverVersion" => "Build 10.38.1c, Aug 4, 2025 2:10:48 PM"
          }
        }
      }
    }
  end

  # IBKR's actual message format for system messages
  let(:system_success_message) do
    {
      topic: "system",
      success: "fukujy152",
      isFT: false,
      isPaper: false
    }
  end

  # IBKR's actual authentication status message
  let(:auth_status_message) do
    {
      topic: "sts",
      args: {
        connected: true,
        authenticated: true,
        competing: false,
        message: "",
        fail: "",
        serverName: "JifZ30006",
        serverVersion: "Build 10.38.1c, Aug 4, 2025 2:10:48 PM",
        username: "fukujy152"
      }
    }
  end

  # IBKR's account information message
  let(:account_info_message) do
    {
      topic: "act",
      args: {
        accounts: ["U18282243"],
        acctProps: {
          "U18282243" => {
            hasChildAccounts: false,
            supportsCashQty: true,
            liteUnderPro: false,
            noFXConv: false
          }
        },
        aliases: {"U18282243" => "reforge"},
        selectedAccount: "U18282243",
        sessionId: "68a00752.00000103"
      }
    }
  end

  # IBKR ping response
  let(:ping_response) do
    {
      topic: "tic",
      alive: true,
      id: mock_session_token,
      lastAccessed: Time.now.to_i * 1000
    }
  end

  # IBKR heartbeat message
  let(:heartbeat_message) do
    {
      topic: "system",
      hb: Time.now.to_i * 1000
    }
  end

  # Mock OAuth client with ping method for /tickle endpoint
  before do
    allow(oauth_client).to receive(:ping).and_return(tickle_response)
  end
end

RSpec.shared_context "with WebSocket subscriptions" do
  include_context "with WebSocket authentication"

  # IBKR account summary subscription response
  let(:account_summary_response) do
    {
      result: [],
      topic: "ssd+U18282243"
    }
  end

  # IBKR account summary data update
  let(:account_summary_data) do
    {
      topic: "ssd+U18282243",
      args: {
        data: [
          {
            key: "NetLiquidation-S",
            value: "125000.50",
            currency: "USD"
          },
          {
            key: "TotalCashValue-S",
            value: "25000.00",
            currency: "USD"
          }
        ]
      }
    }
  end

  # IBKR subscription error (e.g., invalid topic)
  let(:subscription_error_response) do
    {
      error: "Topic unknown",
      code: 1,
      topic: "invalid_topic"
    }
  end

  # IBKR subscription success response
  let(:subscription_success_response) do
    {
      status: "success",
      message: "Subscription confirmed"
    }
  end

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
    # Mock EventMachine.reactor_running? to return true
    allow(EventMachine).to receive(:reactor_running?).and_return(true)

    # Mock EventMachine.run to execute block immediately
    allow(EventMachine).to receive(:run) do |&block|
      block&.call
    end

    # Mock EventMachine.stop
    allow(EventMachine).to receive(:stop)

    # Mock EventMachine.next_tick to execute immediately
    allow(EventMachine).to receive(:next_tick) do |&block|
      block&.call
    end

    # Mock EventMachine timers - Execute short delays immediately, skip long delays (timeouts)
    allow(EventMachine).to receive(:add_timer) do |delay, &block|
      # Execute callbacks for short delays (like ping timers) but not long delays (timeouts)
      if delay <= 2  # Execute timers with delay <= 2 seconds (ping timers)
        block&.call
      end
      # Return a timer mock for all cases
      double("timer", cancel: nil)
    end

    allow(EventMachine).to receive(:add_periodic_timer) do |interval, &block|
      double("periodic_timer", cancel: nil)
    end
  end
end
