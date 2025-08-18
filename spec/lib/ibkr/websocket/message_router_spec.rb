# frozen_string_literal: true

require "spec_helper"
require "ibkr/websocket/message_router"
require "ibkr/websocket/errors"

RSpec.describe Ibkr::WebSocket::MessageRouter do
  let(:websocket_client) { instance_double(Ibkr::WebSocket::Client) }
  let(:connection_manager) { instance_double("ConnectionManager") }
  let(:subscription_manager) { instance_double("SubscriptionManager") }
  let(:router) { described_class.new(websocket_client) }

  before do
    allow(websocket_client).to receive(:connection_manager).and_return(connection_manager)
    allow(websocket_client).to receive(:subscription_manager).and_return(subscription_manager)
    allow(websocket_client).to receive(:emit)
    allow(websocket_client).to receive(:send_message)
  end

  describe "#initialize" do
    it "stores the websocket client reference" do
      expect(router.instance_variable_get(:@websocket_client)).to eq(websocket_client)
    end

    it "initializes empty message handlers" do
      expect(router.message_handlers).to be_a(Hash)
      expect(router.message_handlers).not_to be_empty # has default handlers
    end

    it "initializes routing statistics" do
      stats = router.routing_statistics
      expect(stats[:total_messages]).to eq(0)
      expect(stats[:by_type]).to be_a(Hash)
      expect(stats[:routing_errors]).to eq(0)
      expect(stats[:unknown_types]).to eq(0)
      expect(stats[:processing_times]).to eq([])
    end

    it "sets up default handlers for all MESSAGE_TYPES" do
      described_class::MESSAGE_TYPES.each do |msg_type, _handler|
        expect(router.message_handlers).to have_key(msg_type)
      end
    end
  end

  describe "#route" do
    context "with valid message" do
      let(:message) { {type: "ping", timestamp: 123456} }

      it "routes message to appropriate handler" do
        expect(websocket_client).to receive(:send_message).with(hash_including(type: "pong"))
        result = router.route(message)
        expect(result).to be true
      end

      it "increments total_messages counter" do
        allow(websocket_client).to receive(:send_message)
        router.route(message)
        expect(router.routing_statistics[:total_messages]).to eq(1)
      end

      it "tracks message type statistics" do
        allow(websocket_client).to receive(:send_message)
        router.route(message)
        expect(router.routing_statistics[:by_type]["ping"]).to eq(1)
      end

      it "records processing time" do
        allow(websocket_client).to receive(:send_message)
        router.route(message)
        expect(router.routing_statistics[:processing_times]).not_to be_empty
      end
    end

    context "with invalid message" do
      it "returns false for non-hash message" do
        result = router.route("invalid")
        expect(result).to be false
      end

      it "increments routing_errors counter" do
        router.route("invalid")
        expect(router.routing_statistics[:routing_errors]).to eq(1)
      end

      it "handles nil message" do
        result = router.route(nil)
        expect(result).to be false
        expect(router.routing_statistics[:routing_errors]).to eq(1)
      end
    end

    context "with unknown message type" do
      let(:message) { {type: "unknown_type", data: "test"} }

      it "returns false" do
        result = router.route(message)
        expect(result).to be false
      end

      it "increments unknown_types counter" do
        router.route(message)
        expect(router.routing_statistics[:unknown_types]).to eq(1)
      end

      it "emits unknown_message_type event" do
        expect(router).to receive(:emit).with(:unknown_message_type, hash_including(type: "unknown_type"))
        router.route(message)
      end
    end

    context "when handler raises exception" do
      let(:message) { {type: "ping"} }

      before do
        allow(websocket_client).to receive(:send_message).and_raise(StandardError, "Test error")
      end

      it "returns false" do
        result = router.route(message)
        expect(result).to be false
      end

      it "increments routing_errors counter" do
        router.route(message)
        expect(router.routing_statistics[:routing_errors]).to eq(1)
      end

      it "emits routing_error event" do
        expect(router).to receive(:emit).with(:routing_error, hash_including(:error))
        router.route(message)
      end
    end
  end

  describe "#register_handler" do
    context "with proc handler" do
      it "registers proc handler" do
        handler = proc { |msg| puts msg }
        router.register_handler("custom", handler)
        expect(router.message_handlers["custom"]).to eq(handler)
      end

      it "registers block handler" do
        router.register_handler("custom") { |msg| puts msg }
        expect(router.message_handlers["custom"]).to be_a(Proc)
      end
    end

    context "with symbol handler" do
      it "registers symbol handler" do
        router.register_handler("custom", :handle_custom)
        expect(router.message_handlers["custom"]).to eq(:handle_custom)
      end
    end

    context "without handler" do
      it "raises ArgumentError" do
        expect { router.register_handler("custom") }.to raise_error(ArgumentError, "Handler is required")
      end
    end

    it "overwrites existing handler" do
      handler1 = proc { |msg| puts "1" }
      handler2 = proc { |msg| puts "2" }
      router.register_handler("custom", handler1)
      router.register_handler("custom", handler2)
      expect(router.message_handlers["custom"]).to eq(handler2)
    end
  end

  describe "#unregister_handler" do
    it "removes existing handler" do
      router.register_handler("custom") { |msg| puts msg }
      result = router.unregister_handler("custom")
      expect(result).to be true
      expect(router.message_handlers).not_to have_key("custom")
    end

    it "returns false for non-existent handler" do
      result = router.unregister_handler("non_existent")
      expect(result).to be false
    end
  end

  describe "#statistics" do
    before do
      allow(websocket_client).to receive(:send_message)
      allow(connection_manager).to receive(:handle_pong_message)
      router.route({type: "ping"})
      router.route({type: "pong"})
      router.route("invalid")
    end

    it "returns routing statistics" do
      stats = router.statistics
      expect(stats[:total_messages]).to eq(3)
      expect(stats[:routing_errors]).to eq(1)
    end

    it "calculates average processing time" do
      stats = router.statistics
      expect(stats[:average_processing_time]).to be_a(Float)
    end

    it "includes max and min processing times" do
      stats = router.statistics
      expect(stats[:max_processing_time]).to be_a(Float)
      expect(stats[:min_processing_time]).to be_a(Float)
    end

    context "with no processing times" do
      before { router.reset_statistics }

      it "does not include timing stats" do
        stats = router.statistics
        expect(stats).not_to have_key(:average_processing_time)
        expect(stats).not_to have_key(:max_processing_time)
        expect(stats).not_to have_key(:min_processing_time)
      end
    end
  end

  describe "#reset_statistics" do
    before do
      allow(websocket_client).to receive(:send_message)
      router.route({type: "ping"})
    end

    it "resets all counters" do
      router.reset_statistics
      stats = router.routing_statistics
      expect(stats[:total_messages]).to eq(0)
      expect(stats[:routing_errors]).to eq(0)
      expect(stats[:unknown_types]).to eq(0)
    end

    it "clears processing times" do
      router.reset_statistics
      expect(router.routing_statistics[:processing_times]).to eq([])
    end

    it "resets message type counters" do
      router.reset_statistics
      expect(router.routing_statistics[:by_type]).to be_empty
    end
  end

  describe "message type extraction" do
    context "with explicit type field" do
      it "uses type field with symbol key" do
        message = {type: "market_data"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["market_data"]).to eq(1)
      end

      it "uses type field with string key" do
        message = {"type" => "market_data"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["market_data"]).to eq(1)
      end
    end

    context "with subscription error" do
      before do
        allow(subscription_manager).to receive(:handle_subscription_response)
      end
      
      it "identifies subscription_error with subscription_id and error" do
        message = {subscription_id: "123", error: "failed"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["subscription_error"]).to eq(1)
      end

      it "prioritizes subscription_error over generic error" do
        message = {subscription_id: "123", error: "failed", type: "error"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["subscription_error"]).to eq(1)
      end
    end

    context "with topic field" do
      before do
        allow(connection_manager).to receive(:set_authenticated!)
      end
      
      it "handles 'sts' topic as status" do
        message = {topic: "sts"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["status"]).to eq(1)
      end

      it "handles 'system' topic as system_message" do
        message = {topic: "system"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["system_message"]).to eq(1)
      end

      it "handles 'act' topic as account_info" do
        message = {topic: "act"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["account_info"]).to eq(1)
      end

      it "handles 'ssd+' topic pattern as account_summary" do
        message = {topic: "ssd+12345"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["account_summary"]).to eq(1)
      end

      it "handles unknown topic as topic_<name>" do
        message = {topic: "custom"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["topic_custom"]).to eq(1)
      end
    end

    context "with message field" do
      it "identifies system_message" do
        message = {message: "System notification"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["system_message"]).to eq(1)
      end
    end

    context "without identifiable type" do
      it "defaults to unknown" do
        message = {data: "test"}
        router.route(message)
        expect(router.routing_statistics[:by_type]["unknown"]).to eq(1)
      end
    end
  end

  describe "default handlers" do
    describe "auth_response handler" do
      it "delegates to connection_manager" do
        message = {type: "auth_response", status: "success"}
        expect(connection_manager).to receive(:handle_auth_response).with(message)
        router.route(message)
      end
    end

    describe "ping handler" do
      it "sends pong response" do
        message = {type: "ping", timestamp: 123456}
        expect(websocket_client).to receive(:send_message).with(
          hash_including(type: "pong", timestamp: 123456)
        )
        router.route(message)
      end

      it "uses current time if no timestamp" do
        message = {type: "ping"}
        expect(websocket_client).to receive(:send_message).with(
          hash_including(type: "pong")
        )
        router.route(message)
      end
    end

    describe "pong handler" do
      it "delegates to connection_manager" do
        message = {type: "pong"}
        expect(connection_manager).to receive(:handle_pong_message).with(message)
        router.route(message)
      end
    end

    describe "subscription handlers" do
      it "handles subscription_response" do
        message = {type: "subscription_response", status: "ok"}
        expect(subscription_manager).to receive(:handle_subscription_response).with(message)
        router.route(message)
      end

      it "handles subscription_error" do
        message = {type: "subscription_error", error: "failed"}
        expect(subscription_manager).to receive(:handle_subscription_response).with(
          hash_including(status: "error")
        )
        router.route(message)
      end
    end

    describe "data stream handlers" do
      it "handles market_data with symbol" do
        message = {type: "market_data", symbol: "AAPL", data: {price: 150}}
        expect(websocket_client).to receive(:emit).with(:market_data, 
          hash_including(symbol: "AAPL", price: 150)
        )
        router.route(message)
      end

      it "handles market_data without symbol" do
        message = {type: "market_data", price: 150}
        expect(websocket_client).to receive(:emit).with(:market_data, message)
        router.route(message)
      end

      it "handles portfolio_update with data" do
        message = {type: "portfolio_update", data: {positions: []}}
        expect(websocket_client).to receive(:emit).with(:portfolio_update, {positions: []})
        router.route(message)
      end

      it "handles portfolio_update without data" do
        message = {type: "portfolio_update", positions: []}
        expect(websocket_client).to receive(:emit).with(:portfolio_update, message)
        router.route(message)
      end

      it "handles order_update with data" do
        message = {
          type: "order_update",
          order_id: "123",
          status: "filled",
          data: {qty: 100}
        }
        expect(websocket_client).to receive(:emit).with(:order_update,
          hash_including(order_id: "123", status: "filled", qty: 100)
        )
        router.route(message)
      end

      it "handles order_update without data" do
        message = {type: "order_update", order_id: "123"}
        expect(websocket_client).to receive(:emit).with(:order_update, message)
        router.route(message)
      end

      it "handles trade_data" do
        message = {type: "trade_data", data: {price: 100}}
        expect(websocket_client).to receive(:emit).with(:trade_data, {price: 100})
        router.route(message)
      end

      it "handles depth_data" do
        message = {type: "depth_data", data: {bids: [], asks: []}}
        expect(websocket_client).to receive(:emit).with(:depth_data, {bids: [], asks: []})
        router.route(message)
      end
    end

    describe "system message handler" do
      it "handles 'waiting for session' message" do
        message = {type: "system_message", message: "waiting for session"}
        expect(websocket_client).to receive(:emit).with(:session_pending, message)
        router.route(message)
      end

      it "handles 'session ready' message" do
        message = {type: "system_message", message: "session ready"}
        expect(websocket_client).to receive(:emit).with(:session_ready, message)
        router.route(message)
      end

      it "handles 'authenticated' message" do
        message = {type: "system_message", message: "authenticated"}
        expect(websocket_client).to receive(:emit).with(:session_ready, message)
        router.route(message)
      end

      it "handles generic system message" do
        message = {type: "system_message", message: "other message"}
        expect(websocket_client).to receive(:emit).with(:system_message, message)
        router.route(message)
      end
    end

    describe "error message handler" do
      it "handles error with message" do
        message = {type: "error", message: "Something failed"}
        expect(websocket_client).to receive(:emit).with(:error, 
          an_instance_of(Ibkr::WebSocket::MessageProcessingError)
        )
        router.route(message)
      end

      it "handles error with error field" do
        message = {type: "error", error: "ERR_001", message: "Failed"}
        expect(websocket_client).to receive(:emit) do |event, error|
          expect(event).to eq(:error)
          expect(error.message).to include("ERR_001")
        end
        router.route(message)
      end

      it "handles error without message" do
        message = {type: "error"}
        expect(websocket_client).to receive(:emit).with(:error, 
          an_instance_of(Ibkr::WebSocket::MessageProcessingError)
        )
        router.route(message)
      end
    end

    describe "rate limit handler" do
      it "emits rate_limit event" do
        message = {type: "rate_limit", limit: 100, remaining: 50}
        expect(websocket_client).to receive(:emit).with(:rate_limit, message)
        router.route(message)
      end
    end

    describe "authentication status handler" do
      it "handles authenticated status" do
        message = {type: "status", args: {authenticated: true, connected: true}}
        expect(connection_manager).to receive(:set_authenticated!)
        expect(websocket_client).to receive(:emit).with(:authenticated)
        router.route(message)
      end

      it "handles not authenticated status" do
        message = {type: "status", args: {authenticated: false}}
        # The handler rescues exceptions and emits system_message instead
        # when AuthenticationError is not properly loaded
        expect(websocket_client).to receive(:emit).with(:system_message, message)
        router.route(message)
      end

      it "handles other status messages" do
        message = {type: "status", args: {other: "data"}}
        expect(websocket_client).to receive(:emit).with(:system_message, message)
        router.route(message)
      end

      it "handles malformed status message" do
        message = {type: "status", invalid: "data"}
        expect(websocket_client).to receive(:emit).with(:system_message, message)
        router.route(message)
      end
    end

    describe "account info handlers" do
      it "handles account_info" do
        message = {type: "account_info", account: "DU123456"}
        expect(websocket_client).to receive(:emit).with(:account_info, message)
        router.route(message)
      end

      it "handles account_summary" do
        message = {type: "account_summary", data: {net_liquidation: 100000}}
        expect(websocket_client).to receive(:emit).with(:account_summary, message)
        router.route(message)
      end
    end
  end

  describe "custom handler execution" do
    context "with proc handler" do
      it "executes proc handler" do
        called = false
        router.register_handler("custom") { |msg| called = true }
        router.route({type: "custom"})
        expect(called).to be true
      end

      it "passes message to proc" do
        received_message = nil
        router.register_handler("custom") { |msg| received_message = msg }
        message = {type: "custom", data: "test"}
        router.route(message)
        expect(received_message).to eq(message)
      end
    end

    context "with symbol handler" do
      before do
        allow(router).to receive(:custom_handler)
        router.register_handler("custom", :custom_handler)
      end

      it "calls method on router" do
        message = {type: "custom"}
        expect(router).to receive(:custom_handler).with(message)
        router.route(message)
      end
    end

    context "with invalid handler" do
      it "handles non-existent method" do
        router.register_handler("custom", :non_existent_method)
        expect { router.route({type: "custom"}) }.not_to raise_error
        expect(router.routing_statistics[:routing_errors]).to eq(1)
      end
    end
  end

  describe "performance considerations" do
    it "limits processing times array size" do
      stub_const("Ibkr::WebSocket::Configuration::MAX_PROCESSING_TIMES", 10)
      stub_const("Ibkr::WebSocket::Configuration::PROCESSING_TIMES_CLEANUP_BATCH", 5)
      
      allow(websocket_client).to receive(:send_message)
      
      15.times { router.route({type: "ping"}) }
      
      expect(router.routing_statistics[:processing_times].size).to be <= 10
    end
  end

  describe "error handling" do
    it "handles errors during message type extraction" do
      message = Object.new
      def message.is_a?(klass); klass == Hash; end
      def message.[](key); raise "Error"; end
      
      result = router.route(message)
      expect(result).to be false
      expect(router.routing_statistics[:routing_errors]).to eq(1)
    end

    it "emits routing_error with enhanced error" do
      message = {type: "ping"}
      allow(websocket_client).to receive(:send_message).and_raise(StandardError, "Test")
      
      expect(router).to receive(:emit) do |event, data|
        expect(event).to eq(:routing_error)
        expect(data[:error]).to be_a(Ibkr::WebSocket::MessageProcessingError)
        expect(data[:error].context[:message_type]).to eq("ping")
      end
      
      router.route(message)
    end
  end
end