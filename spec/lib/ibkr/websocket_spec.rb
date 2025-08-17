# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::WebSocket do
  include_context "with WebSocket test environment"

  describe "module configuration" do
    it "provides access to WebSocket configuration" do
      expect(described_class).to respond_to(:configuration)
      expect(described_class.configuration).to be_a(Ibkr::WebSocket::Configuration)
    end

    it "allows configuration customization" do
      described_class.configure do |config|
        config.reconnect_attempts = 5
        config.heartbeat_interval = 30
      end

      expect(described_class.configuration.reconnect_attempts).to eq(5)
      expect(described_class.configuration.heartbeat_interval).to eq(30)
    end
  end

  describe "factory methods" do
    let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }

    it "creates WebSocket client through main client" do
      websocket_client = client.websocket
      
      expect(websocket_client).to be_a(Ibkr::WebSocket::Client)
      expect(websocket_client.account_id).to eq("DU123456")
      expect(websocket_client.live_mode?).to be false
    end

    it "creates streaming interfaces" do
      streaming = client.streaming
      
      expect(streaming).to be_a(Ibkr::WebSocket::Streaming)
      expect(streaming.client).to be_a(Ibkr::WebSocket::Client)
    end

    it "provides real-time market data interface" do
      market_data = client.real_time_data
      
      expect(market_data).to be_a(Ibkr::WebSocket::MarketData)
      expect(market_data.websocket_client).to be_a(Ibkr::WebSocket::Client)
    end
  end

  describe "error handling integration" do
    let(:websocket_client) { Ibkr::WebSocket::Client.new(oauth_client: oauth_client, account_id: "DU123456") }

    include_context "with authenticated oauth client"

    it "integrates with enhanced error context" do
      # Given WebSocket operation fails
      allow(Faye::WebSocket::Client).to receive(:new).and_raise(StandardError, "Connection failed")

      # When error occurs
      expect {
        websocket_client.connect
      }.to raise_error(Ibkr::WebSocket::ConnectionError) do |error|
        # Then enhanced error context should be provided
        expect(error.context).to include(:websocket_url)
        expect(error.context).to include(:account_id)
        expect(error.suggestions).to include("check network connectivity")
      end
    end

    it "provides debug information for WebSocket errors" do
      websocket_client.connect
      simulate_websocket_error("WebSocket error")

      error = websocket_client.last_error
      expect(error).to be_a(Ibkr::WebSocket::Error)
      expect(error.debug_info).to include(:connection_state)
      expect(error.debug_info).to include(:last_heartbeat)
    end
  end
end