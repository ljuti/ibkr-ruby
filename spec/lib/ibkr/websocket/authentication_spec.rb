# frozen_string_literal: true

require "spec_helper"
require "ibkr/websocket/errors"

RSpec.describe Ibkr::WebSocket::Authentication do
  let(:ibkr_client) { instance_double(Ibkr::Client) }
  let(:authentication) { described_class.new(ibkr_client) }
  let(:session_token) { "test_session_token_123" }
  let(:tickle_response) do
    {
      "session" => session_token,
      "ssoExpires" => Time.now.to_i + 3600,
      "userId" => "user123",
      "result" => true
    }
  end

  describe "#initialize" do
    it "stores the IBKR client reference" do
      expect(authentication.instance_variable_get(:@ibkr_client)).to eq(ibkr_client)
    end

    it "initializes session_token as nil" do
      expect(authentication.session_token).to be_nil
    end

    it "initializes session_data as nil" do
      expect(authentication.session_data).to be_nil
    end
  end

  describe "#authenticated?" do
    context "when session token is nil" do
      it "returns false" do
        expect(authentication.authenticated?).to be false
      end

      it "does not check client authentication" do
        expect(ibkr_client).not_to receive(:authenticated?)
        authentication.authenticated?
      end
    end

    context "when session token exists" do
      before do
        authentication.instance_variable_set(:@session_token, session_token)
      end

      context "and client is authenticated" do
        before do
          allow(ibkr_client).to receive(:authenticated?).and_return(true)
        end

        it "returns true" do
          expect(authentication.authenticated?).to be true
        end
      end

      context "but client is not authenticated" do
        before do
          allow(ibkr_client).to receive(:authenticated?).and_return(false)
        end

        it "returns false" do
          expect(authentication.authenticated?).to be false
        end
      end

      it "delegates to ibkr_client.authenticated?" do
        expect(ibkr_client).to receive(:authenticated?).and_return(true)
        authentication.authenticated?
      end
    end
  end

  describe "#authenticate_websocket" do
    context "when client is not authenticated" do
      before do
        allow(ibkr_client).to receive(:authenticated?).and_return(false)
      end

      it "raises AuthenticationError" do
        expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
          expect(error.message).to include("not authenticated")
          expect(error.context[:operation]).to eq("websocket_authentication_check")
        end
      end
    end

    context "when client is authenticated" do
      before do
        allow(ibkr_client).to receive(:authenticated?).and_return(true)
      end

      context "and tickle endpoint returns valid session" do
        before do
          allow(ibkr_client).to receive(:ping).and_return(tickle_response)
        end

        it "returns JSON string with session token" do
          result = authentication.authenticate_websocket
          expect(result).to be_a(String)
          parsed = JSON.parse(result)
          expect(parsed["session"]).to eq(session_token)
        end

        it "stores the session token" do
          authentication.authenticate_websocket
          expect(authentication.session_token).to eq(session_token)
        end

        it "stores the session data" do
          authentication.authenticate_websocket
          expect(authentication.session_data).to eq(tickle_response)
        end
      end

      context "and tickle endpoint returns nil" do
        before do
          allow(ibkr_client).to receive(:ping).and_return(nil)
        end

        it "raises AuthenticationError" do
          expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
            expect(error.context[:operation]).to eq("websocket_authentication")
          end
        end
      end

      context "and tickle endpoint returns response without session" do
        before do
          allow(ibkr_client).to receive(:ping).and_return({"result" => true})
        end

        it "raises AuthenticationError" do
          expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
            expect(error.context[:operation]).to eq("websocket_authentication")
          end
        end
      end

      context "and tickle endpoint raises an exception" do
        before do
          allow(ibkr_client).to receive(:ping).and_raise(StandardError, "Network error")
        end

        it "raises AuthenticationError with error details" do
          expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
            expect(error.context[:operation]).to eq("websocket_authentication")
            expect(error.context[:error]).to include("Network error")
          end
        end
      end
    end
  end

  describe "#current_token" do
    it "is an alias for session_token" do
      authentication.instance_variable_set(:@session_token, session_token)
      expect(authentication.current_token).to eq(session_token)
    end

    it "returns nil when no token is set" do
      expect(authentication.current_token).to be_nil
    end
  end

  describe "#refresh_token!" do
    context "when client is not authenticated" do
      before do
        allow(ibkr_client).to receive(:authenticated?).and_return(false)
      end

      it "raises AuthenticationError" do
        expect { authentication.refresh_token! }.to raise_error(Ibkr::WebSocket::AuthenticationError)
      end
    end

    context "when client is authenticated" do
      before do
        allow(ibkr_client).to receive(:authenticated?).and_return(true)
        allow(ibkr_client).to receive(:ping).and_return(tickle_response)
      end

      it "fetches new session token" do
        expect(ibkr_client).to receive(:ping).and_return(tickle_response)
        authentication.refresh_token!
      end

      it "returns the new session token" do
        result = authentication.refresh_token!
        expect(result).to eq(session_token)
      end

      it "updates the stored session token" do
        authentication.refresh_token!
        expect(authentication.session_token).to eq(session_token)
      end

      it "replaces existing token" do
        authentication.instance_variable_set(:@session_token, "old_token")
        authentication.refresh_token!
        expect(authentication.session_token).to eq(session_token)
      end
    end
  end

  describe "#websocket_endpoint" do
    context "with sandbox environment" do
      before do
        allow(ibkr_client).to receive(:environment).and_return(:sandbox)
      end

      it "returns sandbox WebSocket URL" do
        expect(authentication.websocket_endpoint).to include("wss://")
        expect(authentication.websocket_endpoint).to include("ibkr.com")
      end
    end

    context "with production environment" do
      before do
        allow(ibkr_client).to receive(:environment).and_return(:production)
      end

      it "returns production WebSocket URL" do
        expect(authentication.websocket_endpoint).to include("wss://")
        expect(authentication.websocket_endpoint).to include("ibkr.com")
      end
    end

    it "delegates to Configuration.websocket_endpoint" do
      allow(ibkr_client).to receive(:environment).and_return(:sandbox)
      expect(Ibkr::WebSocket::Configuration).to receive(:websocket_endpoint).with(:sandbox)
      authentication.websocket_endpoint
    end
  end

  describe "#connection_headers" do
    context "when client is not authenticated" do
      before do
        allow(ibkr_client).to receive(:authenticated?).and_return(false)
      end

      it "raises AuthenticationError" do
        expect { authentication.connection_headers }.to raise_error(Ibkr::WebSocket::AuthenticationError)
      end
    end

    context "when client is authenticated" do
      before do
        allow(ibkr_client).to receive(:authenticated?).and_return(true)
        allow(ibkr_client).to receive(:ping).and_return(tickle_response)
      end

      it "returns headers with Cookie" do
        headers = authentication.connection_headers
        expect(headers["Cookie"]).to eq("api=#{session_token}")
      end

      it "includes default headers" do
        headers = authentication.connection_headers
        expect(headers["User-Agent"]).to include("IBKR-Ruby")
      end

      it "fetches fresh session token" do
        expect(ibkr_client).to receive(:ping).and_return(tickle_response)
        authentication.connection_headers
      end

      it "updates stored session token" do
        authentication.connection_headers
        expect(authentication.session_token).to eq(session_token)
      end
    end
  end

  describe "#token_valid?" do
    context "when session token is nil" do
      it "returns false" do
        expect(authentication.token_valid?).to be false
      end
    end

    context "when session token exists" do
      before do
        authentication.instance_variable_set(:@session_token, session_token)
      end

      it "returns true" do
        expect(authentication.token_valid?).to be true
      end
    end

    context "when session token is empty string" do
      before do
        authentication.instance_variable_set(:@session_token, "")
      end

      it "returns true" do
        expect(authentication.token_valid?).to be true
      end
    end
  end

  describe "#token_expires_in" do
    context "when session_data is nil" do
      it "returns nil" do
        expect(authentication.token_expires_in).to be_nil
      end
    end

    context "when session_data exists but ssoExpires is missing" do
      before do
        authentication.instance_variable_set(:@session_data, {"session" => "token"})
      end

      it "returns nil" do
        expect(authentication.token_expires_in).to be_nil
      end
    end

    context "when ssoExpires is not an integer" do
      before do
        authentication.instance_variable_set(:@session_data, {"ssoExpires" => "invalid"})
      end

      it "returns nil" do
        expect(authentication.token_expires_in).to be_nil
      end
    end

    context "when ssoExpires is valid" do
      let(:expiry_time) { Time.now.to_i + 3600 }

      before do
        authentication.instance_variable_set(:@session_data, {"ssoExpires" => expiry_time})
      end

      it "returns seconds until expiration" do
        result = authentication.token_expires_in
        expect(result).to be_between(3598, 3600)
      end

      it "returns negative value when expired" do
        authentication.instance_variable_set(:@session_data, {"ssoExpires" => Time.now.to_i - 100})
        expect(authentication.token_expires_in).to be < 0
      end
    end
  end

  describe "#handle_auth_response" do
    context "with successful authentication" do
      it "returns true for 'success' status" do
        response = {status: "success"}
        expect(authentication.handle_auth_response(response)).to be true
      end

      it "returns true for 'authenticated' status" do
        response = {status: "authenticated"}
        expect(authentication.handle_auth_response(response)).to be true
      end

      it "handles string keys" do
        response = {"status" => "success"}
        expect(authentication.handle_auth_response(response)).to be true
      end

      it "handles mixed key types" do
        response = {:status => "success", "data" => "test"}
        expect(authentication.handle_auth_response(response)).to be true
      end
    end

    context "with failed authentication" do
      it "raises error for 'error' status" do
        response = {status: "error", error: "AUTH_001", message: "Invalid token"}
        expect { authentication.handle_auth_response(response) }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
          expect(error.context[:error_code]).to eq("AUTH_001")
          expect(error.context[:message]).to eq("Invalid token")
        end
      end

      it "raises error for 'failed' status" do
        response = {status: "failed"}
        expect { authentication.handle_auth_response(response) }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
          expect(error.context[:message]).to eq("Authentication failed")
        end
      end

      it "includes full response in error context" do
        response = {status: "error", additional: "data"}
        expect { authentication.handle_auth_response(response) }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
          expect(error.context[:response]).to eq(response)
        end
      end
    end

    context "with unexpected status" do
      it "raises error for unknown status" do
        response = {status: "unknown"}
        expect { authentication.handle_auth_response(response) }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
          expect(error.context[:unexpected_status]).to eq("unknown")
        end
      end

      it "raises error for nil status" do
        response = {data: "test"}
        expect { authentication.handle_auth_response(response) }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
          expect(error.context[:unexpected_status]).to be_nil
        end
      end

      it "includes response in error context" do
        response = {status: "pending", info: "waiting"}
        expect { authentication.handle_auth_response(response) }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
          expect(error.context[:response]).to eq(response)
        end
      end
    end
  end

  describe "error handling edge cases" do
    it "preserves error context in nested rescues" do
      allow(ibkr_client).to receive(:authenticated?).and_return(true)
      allow(ibkr_client).to receive(:ping).and_raise(StandardError, "Original error")

      expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError) do |error|
        expect(error.context[:error]).to eq("Original error")
      end
    end

    it "handles nil response edge case in get_session_token_from_tickle" do
      allow(ibkr_client).to receive(:authenticated?).and_return(true)
      allow(ibkr_client).to receive(:ping).and_return(nil)

      expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError)
    end
  end

  describe "type checking specifics" do
    context "in token_expires_in" do
      it "rejects non-integer numeric types" do
        authentication.instance_variable_set(:@session_data, {"ssoExpires" => 123.45})
        expect(authentication.token_expires_in).to be_nil
      end

      it "accepts only Integer type for ssoExpires" do
        authentication.instance_variable_set(:@session_data, {"ssoExpires" => Time.now.to_i})
        expect(authentication.token_expires_in).not_to be_nil
      end
    end
  end

  describe "edge cases" do
    describe "concurrent token refresh" do
      it "handles multiple refresh calls" do
        allow(ibkr_client).to receive(:authenticated?).and_return(true)
        allow(ibkr_client).to receive(:ping).and_return(tickle_response)

        threads = 3.times.map do
          Thread.new { authentication.refresh_token! }
        end

        results = threads.map(&:join).map(&:value)
        expect(results).to all(eq(session_token))
      end
    end

    describe "error recovery" do
      it "can authenticate after previous failure" do
        allow(ibkr_client).to receive(:authenticated?).and_return(true)
        allow(ibkr_client).to receive(:ping).and_return(nil, tickle_response)

        # First attempt fails
        expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError)

        # Second attempt succeeds
        result = authentication.authenticate_websocket
        expect(JSON.parse(result)["session"]).to eq(session_token)
      end
    end

    describe "state consistency" do
      it "maintains consistent state after errors" do
        allow(ibkr_client).to receive(:authenticated?).and_return(false)

        expect { authentication.authenticate_websocket }.to raise_error(Ibkr::WebSocket::AuthenticationError)

        expect(authentication.session_token).to be_nil
        expect(authentication.session_data).to be_nil
        expect(authentication.authenticated?).to be false
      end
    end
  end
end
