# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Interactive Brokers WebSocket Authentication", type: :feature do
  include_context "with WebSocket test environment"
  include_context "with WebSocket authentication"

  let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }
  let(:websocket_client) { client.websocket }

  describe "WebSocket authentication flow" do
    context "when user establishes WebSocket connection" do
      it "successfully authenticates using OAuth token", :security do
        # Given a user has a valid OAuth session
        expect(valid_token).to be_valid
        expect(oauth_client).to be_authenticated

        # When they establish a WebSocket connection
        websocket_client.connect
        simulate_websocket_open

        # Then authentication should be automatic using existing token
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          expect(parsed["type"]).to eq("auth")
          expect(parsed["token"]).to eq(valid_token.token)
        end

        # And authentication should succeed
        simulate_websocket_message(auth_success_response)
        expect(websocket_client.authenticated?).to be true
        expect(websocket_client.session_id).to eq("ws_session_123")
      end

      it "handles authentication failures gracefully" do
        # Given a user has an invalid or expired token
        invalid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "invalid_token",
          valid?: false,
          expired?: true)
        allow(oauth_client).to receive(:live_session_token).and_return(invalid_token)

        # When they attempt to authenticate via WebSocket
        websocket_client.connect
        simulate_websocket_open

        # Then authentication should fail with clear error
        simulate_websocket_message(auth_failure_response)
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.last_auth_error).to include("invalid_token")
      end

      it "refreshes expired tokens during WebSocket authentication" do
        # Given a user has an expired token that can be refreshed
        expired_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "expired_token",
          valid?: false,
          expired?: true)
        
        fresh_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "fresh_token",
          valid?: true,
          expired?: false)

        allow(oauth_client).to receive(:live_session_token).and_return(expired_token, fresh_token)
        allow(oauth_client).to receive(:refresh_token).and_return(true)

        # When they connect via WebSocket
        websocket_client.connect
        simulate_websocket_open

        # Then token should be refreshed and authentication should succeed
        expect(oauth_client).to have_received(:refresh_token)
        
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          expect(parsed["token"]).to eq("fresh_token")
        end
      end
    end

    context "when authentication state changes" do
      it "handles OAuth session expiration during WebSocket session" do
        # Given an authenticated WebSocket connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)
        expect(websocket_client.authenticated?).to be true

        # When the OAuth session expires
        session_expired_message = {
          type: "auth_expired",
          message: "Session expired",
          expires_at: Time.now.to_i
        }
        simulate_websocket_message(session_expired_message)

        # Then WebSocket should handle reauthentication
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.reauthentication_required?).to be true
      end

      it "automatically reauthenticates after OAuth token refresh" do
        # Given an authenticated WebSocket with expired session
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        session_expired = {
          type: "auth_expired",
          message: "Session expired"
        }
        simulate_websocket_message(session_expired)
        expect(websocket_client.authenticated?).to be false

        # When OAuth client gets a fresh token
        allow(oauth_client).to receive(:refresh_token).and_return(true)
        fresh_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "fresh_token_123",
          valid?: true,
          expired?: false)
        allow(oauth_client).to receive(:live_session_token).and_return(fresh_token)

        # Then WebSocket should automatically reauthenticate
        websocket_client.reauthenticate
        
        fresh_auth_response = auth_success_response.dup
        fresh_auth_response[:session_id] = "ws_session_456"
        simulate_websocket_message(fresh_auth_response)

        expect(websocket_client.authenticated?).to be true
        expect(websocket_client.session_id).to eq("ws_session_456")
      end
    end

    context "when using live trading credentials", :security do
      let(:live_client) { Ibkr::Client.new(default_account_id: "DU789012", live: true) }
      let(:live_websocket) { live_client.websocket }

      it "applies enhanced security for live trading WebSocket connections" do
        # Given a user connecting to live trading environment
        live_oauth = instance_double("Ibkr::Oauth::Client",
          authenticated?: true,
          live_session_token: valid_token)
        allow(live_client).to receive(:oauth_client).and_return(live_oauth)

        # When establishing WebSocket connection
        live_websocket.connect
        simulate_websocket_open

        # Then enhanced security measures should be applied
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          expect(parsed["type"]).to eq("auth")
          expect(parsed).to have_key("signature")  # Additional signature for live trading
          expect(parsed["environment"]).to eq("live")
        end
      end

      it "requires additional verification for live trading subscriptions" do
        # Given authenticated live trading WebSocket
        live_oauth = instance_double("Ibkr::Oauth::Client",
          authenticated?: true,
          live_session_token: valid_token)
        allow(live_client).to receive(:oauth_client).and_return(live_oauth)

        live_websocket.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When subscribing to market data in live mode
        live_websocket.subscribe_market_data(["AAPL"], ["price"])

        # Then additional verification should be required
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          if parsed["type"] == "subscribe"
            expect(parsed).to have_key("verification")
            expect(parsed["environment"]).to eq("live")
          end
        end
      end
    end
  end

  describe "Security validation and compliance" do
    context "when validating connection security", :security do
      it "enforces secure WebSocket connections (WSS)" do
        # Given a WebSocket client configuration
        # When connecting
        websocket_client.connect

        # Then connection should use secure protocol
        expect(Faye::WebSocket::Client).to have_received(:new) do |url, protocols, options|
          expect(url).to start_with("wss://")
          expect(options[:headers]).to include("User-Agent")
        end
      end

      it "validates SSL certificates in live trading mode" do
        # Given live trading WebSocket client
        live_client = Ibkr::Client.new(live: true)
        live_websocket = live_client.websocket

        # When connecting to live environment
        live_websocket.connect

        # Then SSL verification should be enforced
        expect(Faye::WebSocket::Client).to have_received(:new) do |url, protocols, options|
          expect(options[:tls]).to include(verify_peer: true)
        end
      end

      it "protects against token leakage in logs" do
        # Given WebSocket authentication
        websocket_client.connect
        simulate_websocket_open

        # When authentication messages are sent
        # Then sensitive data should not appear in logs
        expect(Rails.logger).not_to have_received(:debug).with(/valid_token/)
        expect(Rails.logger).not_to have_received(:info).with(/valid_token/)
      end
    end

    context "when handling authentication errors" do
      it "implements secure error reporting" do
        # Given authentication failure
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_failure_response)

        # When checking error details
        error = websocket_client.last_auth_error

        # Then error should not expose sensitive information
        expect(error).not_to include(valid_token.token)
        expect(error).not_to include("password")
        expect(error).not_to include("secret")
        expect(error).to include("Authentication failed")
      end

      it "rate limits authentication attempts" do
        # Given multiple failed authentication attempts
        websocket_client.connect
        simulate_websocket_open

        # When rapid authentication failures occur
        5.times do
          simulate_websocket_message(auth_failure_response)
        end

        # Then rate limiting should be applied
        expect(websocket_client.auth_rate_limited?).to be true
        expect(websocket_client.auth_retry_after).to be > 0
      end
    end
  end

  describe "Session management and lifecycle" do
    context "when managing WebSocket sessions" do
      it "maintains session heartbeat to prevent timeouts" do
        # Given an authenticated WebSocket connection
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When session is idle
        allow(Time).to receive(:now).and_return(Time.now + 30)

        # Then heartbeat should be sent automatically
        expect(mock_websocket).to have_received(:send) do |message|
          parsed = JSON.parse(message)
          expect(parsed["type"]).to eq("ping") if parsed["type"] == "ping"
        end
      end

      it "handles session timeout gracefully" do
        # Given an established WebSocket session
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)

        # When session timeout occurs
        timeout_message = {
          type: "session_timeout",
          message: "Session expired due to inactivity"
        }
        simulate_websocket_message(timeout_message)

        # Then client should handle timeout and prepare for reconnection
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.session_timeout?).to be true
        expect(websocket_client.reconnection_required?).to be true
      end

      it "cleans up session state on disconnect" do
        # Given an authenticated WebSocket session with active subscriptions
        websocket_client.connect
        simulate_websocket_open
        simulate_websocket_message(auth_success_response)
        websocket_client.subscribe_market_data(["AAPL"], ["price"])

        # When connection is closed
        websocket_client.disconnect

        # Then session state should be cleaned up
        expect(websocket_client.authenticated?).to be false
        expect(websocket_client.session_id).to be_nil
        expect(websocket_client.active_subscriptions).to be_empty
      end
    end
  end
end