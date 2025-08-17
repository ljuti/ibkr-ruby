# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::WebSocket::Client do
  include_context "with WebSocket test environment"
  include_context "with WebSocket authentication"

  let(:websocket_client) do
    described_class.new(
      oauth_client: oauth_client,
      account_id: "DU123456",
      live: false
    )
  end

  describe "initialization" do
    context "when creating WebSocket client" do
      it "initializes with required dependencies" do
        # Given WebSocket client dependencies
        # When creating new client
        client = described_class.new(
          oauth_client: oauth_client,
          account_id: "DU123456",
          live: false
        )

        # Then client should be properly configured
        expect(client.oauth_client).to eq(oauth_client)
        expect(client.account_id).to eq("DU123456")
        expect(client.live_mode?).to be false
        expect(client.connected?).to be false
        expect(client.authenticated?).to be false
      end

      it "validates required parameters" do
        # Given missing OAuth client
        # When creating client without required params
        # Then it should raise configuration error
        expect {
          described_class.new(account_id: "DU123456")
        }.to raise_error(Ibkr::ConfigurationError, /oauth_client is required/)
      end

      it "sets up default configuration" do
        # Given new WebSocket client
        # Then default configuration should be applied
        expect(websocket_client.reconnect_attempts).to eq(5)
        expect(websocket_client.heartbeat_interval).to eq(30)
        expect(websocket_client.connection_timeout).to eq(10)
      end
    end
  end

  describe "connection management" do
    it_behaves_like "a WebSocket connection lifecycle"

    context "when establishing connection" do
      it "connects to correct WebSocket endpoint" do
        # Given WebSocket client
        # When connecting
        websocket_client.connect

        # Then connection should be made to correct endpoint
        expected_url = "wss://api.ibkr.com/v1/api/ws"
        expect(Faye::WebSocket::Client).to have_received(:new).with(
          expected_url,
          [],
          hash_including(headers: hash_including("User-Agent"))
        )
      end

      it "establishes connection state tracking" do
        # Given disconnected client
        expect(websocket_client.connection_state).to eq(:disconnected)

        # When connecting
        websocket_client.connect
        expect(websocket_client.connection_state).to eq(:connecting)

        # When connection opens
        simulate_websocket_open
        expect(websocket_client.connection_state).to eq(:connected)
      end

      it "handles connection timeout" do
        # Given connection that times out
        websocket_client.connect

        # When connection timeout occurs
        allow(Time).to receive(:now).and_return(Time.now + 15)
        
        # Then connection should timeout
        expect(websocket_client.connection_state).to eq(:connection_timeout)
        expect(websocket_client.last_error).to include("timeout")
      end
    end

    context "when connection fails" do
      it "handles connection errors gracefully" do
        # Given connection that fails immediately
        allow(Faye::WebSocket::Client).to receive(:new).and_raise(StandardError, "Connection refused")

        # When attempting to connect
        expect { websocket_client.connect }.to raise_error(Ibkr::WebSocket::ConnectionError)
        expect(websocket_client.connection_state).to eq(:error)
      end

      it "tracks connection error details" do
        # Given connection error
        websocket_client.connect
        simulate_websocket_error("Network unreachable")

        # Then error details should be tracked
        expect(websocket_client.last_error).to include("Network unreachable")
        expect(websocket_client.connection_state).to eq(:error)
        expect(websocket_client.error_count).to eq(1)
      end
    end

    context "when disconnecting" do
      it "closes connection cleanly" do
        # Given established connection
        websocket_client.connect
        simulate_websocket_open
        expect(websocket_client.connected?).to be true

        # When disconnecting
        websocket_client.disconnect

        # Then connection should be closed cleanly
        expect(mock_websocket).to have_received(:close)
        expect(websocket_client.connection_state).to eq(:disconnected)
      end

      it "cleans up connection state" do
        # Given authenticated connection with subscriptions
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)
        websocket_client.subscribe_market_data(["AAPL"], ["price"])

        # When disconnecting
        websocket_client.disconnect

        # Then state should be cleaned up
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.session_id).to be_nil
        expect(websocket_client.active_subscriptions).to be_empty
      end
    end
  end

  describe "authentication integration" do
    context "when authenticating over WebSocket" do
      it "sends authentication message on connection" do
        # Given valid OAuth token
        # When connecting
        websocket_client.connect
        simulate_websocket_open

        # Then authentication message should be sent
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          expect(parsed["type"]).to eq("auth")
          expect(parsed["token"]).to eq(valid_token.token)
          expect(parsed["timestamp"]).to be_a(Integer)
        end
      end

      it "handles successful authentication" do
        # Given connection established
        websocket_client.connect
        simulate_websocket_open

        # When authentication succeeds
        simulate_websocket_message(auth_success_response)

        # Then client should be authenticated
        expect(websocket_client.authenticated?).to be true
        expect(websocket_client.session_id).to eq("ws_session_123")
        expect(websocket_client.authentication_timestamp).to be_a(Time)
      end

      it "handles authentication failure" do
        # Given connection established
        websocket_client.connect
        simulate_websocket_open

        # When authentication fails
        simulate_websocket_message(auth_failure_response)

        # Then authentication state should reflect failure
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.session_id).to be_nil
        expect(websocket_client.last_auth_error).to include("invalid_token")
      end
    end

    context "when token expires during session" do
      it "handles session expiration gracefully" do
        # Given authenticated session
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)
        expect(websocket_client.authenticated?).to be true

        # When session expires
        session_expired = {
          type: "auth_expired",
          message: "Session expired"
        }
        simulate_websocket_message(session_expired)

        # Then authentication state should be updated
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.reauthentication_required?).to be true
      end

      it "attempts automatic reauthentication" do
        # Given expired session
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)
        
        session_expired = { type: "auth_expired" }
        simulate_websocket_message(session_expired)

        # When fresh token is available
        fresh_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "fresh_token",
          valid?: true,
          expired?: false)
        allow(oauth_client).to receive(:live_session_token).and_return(fresh_token)

        # Then reauthentication should be attempted
        websocket_client.reauthenticate
        
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          expect(parsed["type"]).to eq("auth")
          expect(parsed["token"]).to eq("fresh_token")
        end
      end
    end
  end

  describe "message handling" do
    let(:valid_message) { { type: "market_data", data: { symbol: "AAPL", price: 150.0 } } }

    it_behaves_like "a WebSocket message handler"

    context "when processing incoming messages" do
      it "routes messages to appropriate handlers" do
        # Given established connection
        websocket_client.connect
        simulate_websocket_open

        # When different message types are received
        auth_handler_called = false
        data_handler_called = false

        websocket_client.on_auth_response { auth_handler_called = true }
        websocket_client.on_market_data { data_handler_called = true }

        simulate_websocket_message(auth_success_response)
        simulate_websocket_message(market_data_update)

        # Then appropriate handlers should be called
        expect(auth_handler_called).to be true
        expect(data_handler_called).to be true
      end

      it "validates message format" do
        # Given established connection
        websocket_client.connect
        simulate_websocket_open

        # When malformed message is received
        invalid_messages = [
          "not json",
          '{"missing_type": true}',
          '{"type": null}',
          nil
        ]

        invalid_messages.each do |invalid_msg|
          expect {
            simulate_websocket_message(invalid_msg)
          }.not_to raise_error
        end

        # Then errors should be tracked but not crash the client
        expect(websocket_client.message_errors.size).to eq(4)
      end

      it "implements message ordering for time-sensitive data" do
        # Given connection with market data subscription
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        received_messages = []
        websocket_client.on_market_data { |data| received_messages << data }

        # When messages arrive out of order
        older_message = market_data_update.dup
        older_message[:timestamp] = Time.now.to_f - 1
        older_message[:data][:price] = 149.0

        newer_message = market_data_update.dup
        newer_message[:timestamp] = Time.now.to_f
        newer_message[:data][:price] = 151.0

        # Send newer first, then older
        simulate_websocket_message(newer_message)
        simulate_websocket_message(older_message)

        # Then messages should be ordered by timestamp
        expect(received_messages.size).to eq(2)
        expect(received_messages.first[:price]).to eq(149.0)  # Older message first
        expect(received_messages.last[:price]).to eq(151.0)   # Newer message last
      end
    end
  end

  describe "heartbeat and keep-alive" do
    context "when maintaining connection health" do
      it "sends periodic heartbeat messages" do
        # Given authenticated connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When heartbeat interval passes
        allow(Time).to receive(:now).and_return(Time.now + 35)  # Past heartbeat interval

        # Then heartbeat should be sent
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          expect(parsed["type"]).to eq("ping") if parsed["type"] == "ping"
        end
      end

      it "tracks heartbeat responses" do
        # Given connection with heartbeat
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When pong response is received
        pong_response = { type: "pong", timestamp: Time.now.to_f }
        simulate_websocket_message(pong_response)

        # Then heartbeat should be acknowledged
        expect(websocket_client.last_heartbeat_response).to be_within(1).of(Time.now)
        expect(websocket_client.connection_healthy?).to be true
      end

      it "detects connection health issues" do
        # Given connection with missed heartbeats
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When heartbeat responses are missed
        allow(Time).to receive(:now).and_return(Time.now + 120)  # 2 minutes without pong

        # Then connection should be considered unhealthy
        expect(websocket_client.connection_healthy?).to be false
        expect(websocket_client.heartbeat_missed_count).to be > 0
      end
    end
  end

  describe "performance monitoring" do
    context "when tracking WebSocket performance", :websocket_performance do
      it "measures message processing latency" do
        # Given authenticated connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When processing messages
        start_time = Time.now
        simulate_websocket_message(market_data_update)
        end_time = Time.now

        # Then processing time should be tracked
        processing_time = end_time - start_time
        expect(processing_time).to be < 0.01  # Should process in under 10ms
        expect(websocket_client.average_message_processing_time).to be > 0
      end

      it "tracks message throughput" do
        # Given authenticated connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When processing multiple messages
        100.times { simulate_websocket_message(market_data_update) }

        # Then throughput should be measured
        expect(websocket_client.messages_processed).to eq(101)  # Including auth response
        expect(websocket_client.messages_per_second).to be > 0
      end

      it "monitors memory usage during high-frequency updates" do
        # Given authenticated connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        start_memory = GC.stat[:heap_live_slots]

        # When processing many messages
        1000.times do |i|
          update = market_data_update.dup
          update[:data][:price] = 150.0 + (i * 0.01)
          simulate_websocket_message(update)
        end

        end_memory = GC.stat[:heap_live_slots]
        memory_growth = end_memory - start_memory

        # Then memory growth should be reasonable
        expect(memory_growth).to be < 50000  # Less than 50k new objects
      end
    end
  end

  describe "thread safety" do
    context "when handling concurrent operations" do
      it "provides thread-safe message handling" do
        # Given authenticated connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When multiple threads send messages concurrently
        threads = Array.new(5) do |i|
          Thread.new do
            10.times do
              update = market_data_update.dup
              update[:data][:price] = 150.0 + (i * 0.1)
              simulate_websocket_message(update)
            end
          end
        end

        # Then all messages should be processed safely
        threads.each(&:join)
        expect(websocket_client.messages_processed).to be >= 50
      end

      it "handles concurrent subscription management" do
        # Given authenticated connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When multiple threads manage subscriptions
        subscription_threads = Array.new(3) do |i|
          Thread.new do
            websocket_client.subscribe_market_data(["STOCK#{i}"], ["price"])
          end
        end

        subscription_threads.each(&:join)

        # Then subscriptions should be managed safely
        expect(websocket_client.active_subscriptions.size).to eq(3)
      end
    end
  end
end