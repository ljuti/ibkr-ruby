# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Interactive Brokers WebSocket Authentication", type: :feature do
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

  # Reset mocks before each test
  before do
    # Use the same mock setup as the shared context to ensure event handlers work
    allow(Faye::WebSocket::Client).to receive(:new) do |url, protocols, options|
      websocket_events.clear
      mock_websocket
    end
  end

  describe "WebSocket authentication flow" do
    context "when user establishes WebSocket connection" do
      it "successfully authenticates using cookie-based session token" do
        # When they establish a WebSocket connection
        websocket_client.connect

        # Then connection should be in connecting state initially
        expect(websocket_client.connection_state).to eq(:connecting)

        # When WebSocket opens
        simulate_websocket_open
        expect(websocket_client.connection_state).to eq(:authenticating)

        # Expect tic ping to be sent for session activation
        expect(mock_websocket).to have_received(:send).with("tic")

        # When IBKR sends authentication confirmation
        simulate_websocket_message(auth_status_message)

        # Then authentication should succeed
        expect(websocket_client.authenticated?).to be true
        expect(websocket_client.connection_state).to eq(:authenticated)
      end

      it "handles authentication failures gracefully" do
        # Given a user has an invalid session (no session token in tickle response)
        invalid_tickle_response = {
          "hmds" => {"error" => "no bridge"},
          "iserver" => {
            "authStatus" => {
              "authenticated" => false,
              "message" => "Authentication failed"
            }
          }
        }
        allow(oauth_client).to receive(:ping).and_return(invalid_tickle_response)

        # When they attempt to authenticate via WebSocket
        expect {
          websocket_client.connect
        }.to raise_error(Ibkr::WebSocket::AuthenticationError)

        # Then connection should not be established
        expect(websocket_client.authenticated?).to be false
      end

      it "uses fresh session token for each connection" do
        # Given multiple connection attempts
        first_session = "session_token_1"
        second_session = "session_token_2"

        first_response = tickle_response.dup
        first_response["session"] = first_session

        second_response = tickle_response.dup
        second_response["session"] = second_session

        allow(oauth_client).to receive(:ping).and_return(first_response, second_response)

        # Capture WebSocket creation calls
        websocket_calls = []
        allow(Faye::WebSocket::Client).to receive(:new) do |url, protocols, options|
          websocket_calls << {url: url, protocols: protocols, options: options}
          websocket_events.clear
          mock_websocket
        end

        # When connecting multiple times
        websocket_client.connect
        websocket_client.disconnect

        websocket_client.connect

        # Then fresh session token should be used each time
        expect(websocket_calls.length).to eq(2)
        expect(websocket_calls[0][:options][:headers]["Cookie"]).to eq("api=#{first_session}")
        expect(websocket_calls[1][:options][:headers]["Cookie"]).to eq("api=#{second_session}")
      end
    end

    context "when handling connection states" do
      it "properly manages connection state transitions" do
        # When connecting
        websocket_client.connect
        expect(websocket_client.connection_state).to eq(:connecting)

        # When WebSocket opens
        simulate_websocket_open
        expect(websocket_client.connection_state).to eq(:authenticating)

        # When authentication succeeds
        simulate_websocket_message(auth_status_message)
        expect(websocket_client.connection_state).to eq(:authenticated)
        expect(websocket_client.authenticated?).to be true
      end
    end
  end

  describe "Security validation and compliance" do
    context "when validating connection security", :security do
      it "enforces secure WebSocket connections (WSS)" do
        # When connecting
        websocket_client.connect

        # Then connection should use secure protocol
        expect(Faye::WebSocket::Client).to have_received(:new) do |url, protocols, options|
          expect(url).to start_with("wss://")
          expect(options[:headers]).to include("User-Agent")
        end
      end

      it "includes proper authentication headers" do
        # When connecting
        websocket_client.connect

        # Then proper headers should be included
        expect(Faye::WebSocket::Client).to have_received(:new) do |url, protocols, options|
          expect(options[:headers]["Cookie"]).to start_with("api=")
          expect(options[:headers]["User-Agent"]).to include("IBKR-Ruby")
          expect(options[:headers]["Origin"]).to eq("interactivebrokers.github.io")
        end
      end
    end

    context "when managing session lifecycle" do
      it "maintains session heartbeat with IBKR ping format" do
        # Given an authenticated WebSocket connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)

        # Then tic heartbeat should be sent
        expect(mock_websocket).to have_received(:send).with("tic")
      end

      it "handles disconnection gracefully" do
        # Given an authenticated WebSocket session
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_status_message)
        expect(websocket_client.authenticated?).to be true

        # When connection is closed
        websocket_client.disconnect

        # Then session state should be cleaned up
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.connection_state).to eq(:disconnected)
      end
    end
  end
end
