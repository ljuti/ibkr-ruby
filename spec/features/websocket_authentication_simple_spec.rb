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

  describe "WebSocket authentication core functionality" do
    it "uses proper WebSocket endpoint" do
      auth = websocket_client.instance_variable_get(:@connection_manager)
                           .instance_variable_get(:@authentication)
      
      expect(auth.websocket_endpoint).to eq("wss://api.ibkr.com/v1/api/ws")
    end

    it "creates session token from tickle response" do
      auth = websocket_client.instance_variable_get(:@connection_manager)
                           .instance_variable_get(:@authentication)
      
      token = auth.authenticate_websocket
      parsed = JSON.parse(token)
      
      expect(parsed["session"]).to eq(mock_session_token)
    end

    it "generates proper authentication headers with cookie" do
      auth = websocket_client.instance_variable_get(:@connection_manager)
                           .instance_variable_get(:@authentication)
      
      headers = auth.connection_headers
      
      expect(headers["Cookie"]).to eq("api=#{mock_session_token}")
      expect(headers["User-Agent"]).to include("IBKR-Ruby")
      expect(headers["Origin"]).to eq("interactivebrokers.github.io")
    end

    it "properly routes IBKR authentication status messages" do
      # Initially not authenticated
      expect(websocket_client.authenticated?).to be false
      expect(websocket_client.connection_state).to eq(:disconnected)
      
      # Connect and immediately simulate WebSocket opening to prevent timeout
      websocket_client.connect
      simulate_websocket_open
      expect(websocket_client.connection_state).to eq(:authenticating)
      
      # When authentication status message is received
      simulate_websocket_message(auth_status_message)
      
      # Then connection should be authenticated
      expect(websocket_client.connection_state).to eq(:authenticated)
      expect(websocket_client.authenticated?).to be true
    end

    it "handles account summary subscription format correctly" do
      # Connect and authenticate first
      websocket_client.connect
      simulate_websocket_open
      simulate_websocket_message(auth_status_message)
      
      # Capture all WebSocket messages
      sent_messages = []
      allow(mock_websocket).to receive(:send) do |message|
        sent_messages << message
        true
      end
      
      # When subscribing to account summary
      websocket_client.subscribe_account_summary("U18282243", 
        keys: ["NetLiquidation-S"], 
        fields: ["currency", "monetaryValue"]
      )
      
      # Then should send IBKR subscription message (among possibly other messages like pings)
      subscription_message = sent_messages.find { |msg| msg.start_with?("ssd+") }
      expect(subscription_message).not_to be_nil
      expect(subscription_message).to include("NetLiquidation-S")
    end
  end

  describe "Message routing" do
    let(:router) { websocket_client.instance_variable_get(:@message_router) }

    it "extracts correct message types from IBKR messages" do
      expect(router.send(:extract_message_type, {topic: "sts"})).to eq("status")
      expect(router.send(:extract_message_type, {topic: "system"})).to eq("system_message")
      expect(router.send(:extract_message_type, {topic: "act"})).to eq("account_info")
      expect(router.send(:extract_message_type, {topic: "ssd+U18282243"})).to eq("account_summary")
    end

    it "validates messages without requiring type field" do
      # IBKR messages don't always have 'type' field, should not raise error
      expect {
        router.send(:validate_message!, {topic: "system", hb: 123456})
      }.not_to raise_error

      expect {
        router.send(:validate_message!, {message: "waiting for session"})
      }.not_to raise_error
    end
  end

  describe "Configuration usage" do
    it "uses configuration constants instead of magic numbers" do
      expect(Ibkr::WebSocket::Configuration::CONNECTION_TIMEOUT).to eq(10)
      expect(Ibkr::WebSocket::Configuration::HEARTBEAT_INTERVAL).to eq(30)
      expect(Ibkr::WebSocket::Configuration::IBKR_PING_MESSAGE).to eq("tic")
    end

    it "provides correct WebSocket endpoint from configuration" do
      expect(Ibkr::WebSocket::Configuration.websocket_endpoint("production"))
        .to eq("wss://api.ibkr.com/v1/api/ws")
      expect(Ibkr::WebSocket::Configuration.websocket_endpoint("paper"))
        .to eq("wss://api.ibkr.com/v1/api/ws")
    end
  end
end