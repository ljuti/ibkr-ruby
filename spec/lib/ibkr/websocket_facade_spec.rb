# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::WebSocketFacade do
  let(:client) { instance_double(Ibkr::Client, active_account_id: "DU123456") }
  let(:facade) { described_class.new(client) }
  let(:websocket_client) { instance_double(Ibkr::WebSocket::Client) }
  let(:streaming_interface) { instance_double(Ibkr::WebSocket::Streaming) }
  let(:market_data_interface) { instance_double(Ibkr::WebSocket::MarketData) }

  describe "#initialize" do
    it "stores the client reference" do
      expect(facade.client).to eq(client)
    end

    it "initializes with nil websocket_client" do
      expect(facade.instance_variable_get(:@websocket_client)).to be_nil
    end

    it "initializes with nil streaming interface" do
      expect(facade.instance_variable_get(:@streaming)).to be_nil
    end

    it "initializes with nil real_time_data interface" do
      expect(facade.instance_variable_get(:@real_time_data)).to be_nil
    end

    it "initializes all instance variables to nil for lazy loading" do
      new_facade = described_class.new(client)
      expect(new_facade.instance_variable_get(:@websocket_client)).to be_nil
      expect(new_facade.instance_variable_get(:@streaming)).to be_nil
      expect(new_facade.instance_variable_get(:@real_time_data)).to be_nil
    end

    it "does not create services during initialization" do
      # Ensure no service creation happens during init
      expect(Ibkr::WebSocket::Client).not_to receive(:new)
      expect(Ibkr::WebSocket::Streaming).not_to receive(:new)
      expect(Ibkr::WebSocket::MarketData).not_to receive(:new)
      
      described_class.new(client)
    end
  end

  describe "#websocket" do
    it "creates and memoizes a WebSocket::Client instance" do
      expect(Ibkr::WebSocket::Client).to receive(:new).with(client).once.and_return(websocket_client)
      
      result1 = facade.websocket
      result2 = facade.websocket
      
      expect(result1).to eq(websocket_client)
      expect(result2).to eq(websocket_client)
    end

    it "passes the client to WebSocket::Client" do
      expect(Ibkr::WebSocket::Client).to receive(:new).with(client).and_return(websocket_client)
      facade.websocket
    end
  end

  describe "#streaming" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
    end

    it "creates and memoizes a WebSocket::Streaming instance" do
      expect(Ibkr::WebSocket::Streaming).to receive(:new).with(websocket_client).once.and_return(streaming_interface)
      
      result1 = facade.streaming
      result2 = facade.streaming
      
      expect(result1).to eq(streaming_interface)
      expect(result2).to eq(streaming_interface)
    end

    it "passes the websocket client to WebSocket::Streaming" do
      expect(Ibkr::WebSocket::Streaming).to receive(:new).with(websocket_client).and_return(streaming_interface)
      facade.streaming
    end
  end

  describe "#real_time_data" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
    end

    it "creates and memoizes a WebSocket::MarketData instance" do
      expect(Ibkr::WebSocket::MarketData).to receive(:new).with(websocket_client).once.and_return(market_data_interface)
      
      result1 = facade.real_time_data
      result2 = facade.real_time_data
      
      expect(result1).to eq(market_data_interface)
      expect(result2).to eq(market_data_interface)
    end

    it "passes the websocket client to WebSocket::MarketData" do
      expect(Ibkr::WebSocket::MarketData).to receive(:new).with(websocket_client).and_return(market_data_interface)
      facade.real_time_data
    end
  end

  describe "#connect" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
    end

    it "calls connect on the websocket client" do
      expect(websocket_client).to receive(:connect)
      facade.connect
    end

    it "returns self for method chaining" do
      allow(websocket_client).to receive(:connect)
      expect(facade.connect).to eq(facade)
    end
  end

  describe "#with_connection" do
    it "delegates to connect" do
      expect(facade).to receive(:connect).and_return(facade)
      result = facade.with_connection
      expect(result).to eq(facade)
    end

    it "returns self for method chaining" do
      allow(facade).to receive(:websocket).and_return(websocket_client)
      allow(websocket_client).to receive(:connect)
      expect(facade.with_connection).to eq(facade)
    end
  end

  describe "#subscribe_market_data" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
    end

    context "with single symbol string" do
      it "converts to array and subscribes" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL"], ["price"])
        facade.subscribe_market_data("AAPL")
      end
    end

    context "with array of symbols" do
      it "subscribes with the array" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL", "MSFT"], ["price"])
        facade.subscribe_market_data(["AAPL", "MSFT"])
      end
    end

    context "with custom fields" do
      it "uses the provided fields" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL"], ["price", "volume", "bid", "ask"])
        facade.subscribe_market_data("AAPL", fields: ["price", "volume", "bid", "ask"])
      end
    end

    context "with default fields" do
      it "uses price as default field" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL"], ["price"])
        facade.subscribe_market_data("AAPL")
      end
    end

    it "returns self for method chaining" do
      allow(websocket_client).to receive(:subscribe_to_market_data)
      expect(facade.subscribe_market_data("AAPL")).to eq(facade)
    end
  end

  describe "#subscribe_portfolio" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
    end

    context "without account_id" do
      it "uses client's active account" do
        expect(websocket_client).to receive(:subscribe_to_portfolio_updates).with("DU123456")
        facade.subscribe_portfolio
      end
    end

    context "with specific account_id" do
      it "uses the provided account" do
        expect(websocket_client).to receive(:subscribe_to_portfolio_updates).with("DU789012")
        facade.subscribe_portfolio("DU789012")
      end
    end

    context "with nil account_id" do
      it "falls back to client's active account" do
        expect(websocket_client).to receive(:subscribe_to_portfolio_updates).with("DU123456")
        facade.subscribe_portfolio(nil)
      end
    end

    it "returns self for method chaining" do
      allow(websocket_client).to receive(:subscribe_to_portfolio_updates)
      expect(facade.subscribe_portfolio).to eq(facade)
    end
  end

  describe "#subscribe_orders" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
    end

    context "without account_id" do
      it "uses client's active account" do
        expect(websocket_client).to receive(:subscribe_to_order_status).with("DU123456")
        facade.subscribe_orders
      end
    end

    context "with specific account_id" do
      it "uses the provided account" do
        expect(websocket_client).to receive(:subscribe_to_order_status).with("DU789012")
        facade.subscribe_orders("DU789012")
      end
    end

    context "with nil account_id" do
      it "falls back to client's active account" do
        expect(websocket_client).to receive(:subscribe_to_order_status).with("DU123456")
        facade.subscribe_orders(nil)
      end
    end

    it "returns self for method chaining" do
      allow(websocket_client).to receive(:subscribe_to_order_status)
      expect(facade.subscribe_orders).to eq(facade)
    end
  end

  describe "#stream_market_data" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
    end

    context "with single symbol" do
      it "flattens and subscribes" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL"], ["price"])
        facade.stream_market_data("AAPL")
      end
    end

    context "with multiple symbols as arguments" do
      it "flattens and subscribes" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL", "MSFT", "GOOGL"], ["price"])
        facade.stream_market_data("AAPL", "MSFT", "GOOGL")
      end
    end

    context "with nested arrays" do
      it "flattens nested arrays" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL", "MSFT", "GOOGL"], ["price"])
        facade.stream_market_data(["AAPL", ["MSFT", "GOOGL"]])
      end
    end

    context "with custom fields" do
      it "passes fields to subscribe_market_data" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL"], ["bid", "ask"])
        facade.stream_market_data("AAPL", fields: ["bid", "ask"])
      end
    end

    it "returns self for method chaining" do
      allow(websocket_client).to receive(:subscribe_to_market_data)
      expect(facade.stream_market_data("AAPL")).to eq(facade)
    end
  end

  describe "#stream_portfolio" do
    it "delegates to subscribe_portfolio" do
      expect(facade).to receive(:subscribe_portfolio).with(nil).and_return(facade)
      result = facade.stream_portfolio
      expect(result).to eq(facade)
    end

    it "passes account_id to subscribe_portfolio" do
      expect(facade).to receive(:subscribe_portfolio).with("DU789012").and_return(facade)
      facade.stream_portfolio("DU789012")
    end
  end

  describe "#stream_orders" do
    it "delegates to subscribe_orders" do
      expect(facade).to receive(:subscribe_orders).with(nil).and_return(facade)
      result = facade.stream_orders
      expect(result).to eq(facade)
    end

    it "passes account_id to subscribe_orders" do
      expect(facade).to receive(:subscribe_orders).with("DU789012").and_return(facade)
      facade.stream_orders("DU789012")
    end
  end

  describe "method chaining" do
    before do
      allow(facade).to receive(:websocket).and_return(websocket_client)
      allow(websocket_client).to receive(:connect)
      allow(websocket_client).to receive(:subscribe_to_market_data)
      allow(websocket_client).to receive(:subscribe_to_portfolio_updates)
      allow(websocket_client).to receive(:subscribe_to_order_status)
    end

    it "supports fluent interface for complete setup" do
      result = facade
        .with_connection
        .stream_market_data("AAPL", "MSFT")
        .stream_portfolio
        .stream_orders

      expect(result).to eq(facade)
      expect(websocket_client).to have_received(:connect)
      expect(websocket_client).to have_received(:subscribe_to_market_data).with(["AAPL", "MSFT"], ["price"])
      expect(websocket_client).to have_received(:subscribe_to_portfolio_updates).with("DU123456")
      expect(websocket_client).to have_received(:subscribe_to_order_status).with("DU123456")
    end
  end

  describe "client reference consistency" do
    it "stores and returns the client reference" do
      expect(facade.client).to eq(client)
      expect(facade.instance_variable_get(:@client)).to eq(client)
    end

    it "uses the stored client for creating websocket" do
      expect(Ibkr::WebSocket::Client).to receive(:new).with(client).and_return(websocket_client)
      facade.websocket
    end

    it "accesses client's active_account_id in subscribe_portfolio" do
      allow(facade).to receive(:websocket).and_return(websocket_client)
      expect(client).to receive(:active_account_id).and_return("DU123456")
      allow(websocket_client).to receive(:subscribe_to_portfolio_updates)
      facade.subscribe_portfolio
    end

    it "accesses client's active_account_id in subscribe_orders" do
      allow(facade).to receive(:websocket).and_return(websocket_client)
      expect(client).to receive(:active_account_id).and_return("DU123456")
      allow(websocket_client).to receive(:subscribe_to_order_status)
      facade.subscribe_orders
    end
  end

  describe "edge cases" do
    describe "when client has no active account" do
      let(:client_no_account) { instance_double(Ibkr::Client, active_account_id: nil) }
      let(:facade_no_account) { described_class.new(client_no_account) }

      before do
        allow(facade_no_account).to receive(:websocket).and_return(websocket_client)
      end

      it "passes nil to portfolio subscription" do
        expect(websocket_client).to receive(:subscribe_to_portfolio_updates).with(nil)
        facade_no_account.subscribe_portfolio
      end

      it "passes nil to order subscription" do
        expect(websocket_client).to receive(:subscribe_to_order_status).with(nil)
        facade_no_account.subscribe_orders
      end
    end

    describe "with empty symbol array" do
      before do
        allow(facade).to receive(:websocket).and_return(websocket_client)
      end

      it "subscribes with empty array" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with([], ["price"])
        facade.subscribe_market_data([])
      end
    end

    describe "with empty fields array" do
      before do
        allow(facade).to receive(:websocket).and_return(websocket_client)
      end

      it "subscribes with empty fields" do
        expect(websocket_client).to receive(:subscribe_to_market_data).with(["AAPL"], [])
        facade.subscribe_market_data("AAPL", fields: [])
      end
    end
  end
end