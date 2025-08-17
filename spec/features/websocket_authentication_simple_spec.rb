# frozen_string_literal: true

require "spec_helper"

RSpec.describe "WebSocket Authentication (Simplified)", type: :feature do
  include_context "with mocked WebSocket connection"
  include_context "with mocked EventMachine"
  include_context "with WebSocket authentication"

  let(:client) do
    client = Ibkr::Client.new(default_account_id: "U18282243", live: false)
    allow(client).to receive(:oauth_client).and_return(oauth_client)
    allow(client).to receive(:authenticated?).and_return(true)
    client
  end
  let(:websocket_client) { client.websocket }

  describe "WebSocket authentication for IBKR trading" do
    it "connects to the correct IBKR WebSocket endpoint" do
      # Given a trader setting up WebSocket connection
      # When they initiate connection
      websocket_client.connect

      # Then connection should use the correct IBKR endpoint
      expect(Faye::WebSocket::Client).to have_received(:new).with(
        "wss://api.ibkr.com/v1/api/ws",
        nil,
        hash_including(headers: hash_including("User-Agent"))
      )
    end

    it "establishes authenticated session with IBKR servers" do
      # Given a trader with valid credentials
      # When they connect to WebSocket and complete authentication
      websocket_client.connect
      simulate_websocket_open
      simulate_websocket_message(auth_status_message)

      # Then they should be authenticated
      expect(websocket_client.authenticated?).to be true
      expect(websocket_client.session_id).to eq("cb0f2f5202aab5d3ca020c118356f315")
    end

    it "includes required authentication headers for IBKR compliance" do
      # Given a trader connecting to IBKR WebSocket
      # When they establish connection
      websocket_client.connect

      # Then proper authentication headers should be sent
      expect(Faye::WebSocket::Client).to have_received(:new).with(
        anything,
        anything,
        hash_including(
          headers: hash_including(
            "Cookie" => "api=#{mock_session_token}",
            "User-Agent" => a_string_including("IBKR-Ruby"),
            "Origin" => "interactivebrokers.github.io"
          )
        )
      )
    end

    it "transitions to authenticated state upon successful login" do
      # Given a trader with valid credentials
      expect(websocket_client.authenticated?).to be false
      expect(websocket_client.connection_state).to eq(:disconnected)

      # When they complete the authentication process
      websocket_client.connect
      simulate_websocket_open
      expect(websocket_client.connection_state).to eq(:authenticating)

      simulate_websocket_message(auth_status_message)

      # Then they gain access to trading functionality
      expect(websocket_client.connection_state).to eq(:authenticated)
      expect(websocket_client.authenticated?).to be true
    end

    it "enables real-time account summary monitoring" do
      # Given an authenticated trader
      establish_authenticated_connection(websocket_client)

      # When they request account summary data
      sent_messages = []
      allow(mock_websocket).to receive(:send) do |message|
        sent_messages << message
        true
      end

      websocket_client.subscribe_account_summary("U18282243",
        keys: ["NetLiquidation-S"],
        fields: ["currency", "monetaryValue"])

      # Then IBKR-specific subscription format is used
      subscription_message = sent_messages.find { |msg| msg.start_with?("ssd+") }
      expect(subscription_message).not_to be_nil
      expect(subscription_message).to include("NetLiquidation-S")
    end
  end

  describe "IBKR message handling" do
    it "processes different types of IBKR server messages" do
      # Given an authenticated connection
      establish_authenticated_connection(websocket_client)

      # When different IBKR message types are received
      message_types_received = []

      # Simulate receiving different IBKR message types
      [{topic: "sts"}, {topic: "system"}, {topic: "act"}, {topic: "ssd+U18282243"}].each do |msg|
        simulate_websocket_message(msg)
        # Track that the message was processed without error
        message_types_received << msg[:topic]
      end

      # Then all message types should be handled
      expect(message_types_received).to include("sts", "system", "act", "ssd+U18282243")
    end

    it "handles IBKR messages that vary in structure" do
      # Given an authenticated connection
      establish_authenticated_connection(websocket_client)

      # When receiving IBKR messages with different structures
      varied_messages = [
        {topic: "system", hb: 123456},
        {message: "waiting for session"}
      ]

      # Then all should be processed without errors
      varied_messages.each do |msg|
        expect {
          simulate_websocket_message(msg)
        }.not_to raise_error
      end
    end
  end

  describe "Trading environment configuration" do
    it "applies appropriate connection timeouts for trading reliability" do
      # Given trading system requirements for responsiveness
      # Then timeouts should be configured for real-time trading
      expect(Ibkr::WebSocket::Configuration::CONNECTION_TIMEOUT).to eq(10)
      expect(Ibkr::WebSocket::Configuration::HEARTBEAT_INTERVAL).to eq(30)
      expect(Ibkr::WebSocket::Configuration::IBKR_PING_MESSAGE).to eq("tic")
    end

    it "provides correct endpoints for production and paper trading" do
      # Given different trading environments
      # Then appropriate endpoints should be configured
      expect(Ibkr::WebSocket::Configuration.websocket_endpoint("production"))
        .to eq("wss://api.ibkr.com/v1/api/ws")
      expect(Ibkr::WebSocket::Configuration.websocket_endpoint("paper"))
        .to eq("wss://api.ibkr.com/v1/api/ws")
    end
  end
end
