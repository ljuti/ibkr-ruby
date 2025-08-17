# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked IBKR API"

  let(:oauth_client) { described_class.new(live: false) }
  let(:live_oauth_client) { described_class.new(live: true) }

  describe "initialization" do
    context "when setting up for sandbox environment" do
      it "provides sandbox trading environment" do
        # When user creates client for sandbox
        # Then it should be configured for testing/development
        expect(oauth_client.instance_variable_get(:@_live)).to be false
      end

      it "initializes in unauthenticated state" do
        # When client is first created
        # Then user starts in unauthenticated state
        expect(oauth_client.token).to be_nil
        expect(oauth_client.authenticated?).to be false
      end
    end

    context "when setting up for live trading environment" do
      it "provides production trading environment" do
        # When user creates client for live trading
        # Then it should be configured for real trading
        expect(live_oauth_client.instance_variable_get(:@_live)).to be true
      end
    end
  end

  describe "authentication from user perspective" do
    context "when user has valid credentials" do
      before do
        allow(oauth_client).to receive(:live_session_token).and_return(
          instance_double("LiveSessionToken", valid?: true)
        )
      end

      it "enables successful authentication for trading access" do
        # Given user has valid IBKR credentials
        # When they attempt to authenticate
        result = oauth_client.authenticate
        
        # Then authentication should succeed
        expect(result).to be true
        
        # And they should have access to trading operations
        expect(oauth_client.authenticated?).to be true
        expect(oauth_client.token).not_to be_nil
      end

      it "maintains authentication state for session duration" do
        # When user successfully authenticates
        oauth_client.authenticate
        
        # Then they should remain authenticated for trading
        expect(oauth_client.authenticated?).to be true
        expect(oauth_client.token).not_to be_nil
      end
    end

    context "when user has invalid credentials" do
      before do
        allow(oauth_client).to receive(:live_session_token).and_return(
          instance_double("LiveSessionToken", valid?: false)
        )
      end

      it "clearly indicates authentication failure" do
        # Given user has invalid IBKR credentials
        # When they attempt to authenticate
        result = oauth_client.authenticate
        
        # Then authentication should fail clearly
        expect(result).to be false
        expect(oauth_client.authenticated?).to be false
      end
    end
  end

  describe "session token management" do
    include_context "with mocked Faraday client"

    let(:mock_dh_response) { "fedcba654321" }
    let(:mock_signature) { "valid_signature" }
    let(:mock_expiration) { (Time.now + 3600).to_i }
    let(:response_body) do
      {
        "diffie_hellman_response" => mock_dh_response,
        "live_session_token_signature" => mock_signature,
        "live_session_token_expiration" => mock_expiration
      }.to_json
    end

    before do
      allow(oauth_client).to receive(:compute_live_session_token).and_return("computed_token")
    end

    context "when token request succeeds" do
      it "provides valid session token for trading operations" do
        # Given successful server response
        # When requesting session token
        token = oauth_client.live_session_token
        
        # Then user should receive valid token for trading
        expect(token).to be_instance_of(Ibkr::Oauth::LiveSessionToken)
      end

      it "enables secure communication with IBKR servers" do
        # When session token is obtained
        # Then it should enable secure API communication
        token = oauth_client.live_session_token
        expect(token).not_to be_nil
      end
    end

    context "when token request fails" do
      before do
        # Override successful auth mock with failure
        stub_request(:post, "#{base_url}/v1/api/oauth/live_session_token")
          .to_return(status: 401, body: "Unauthorized")
      end

      it "provides clear error for authentication problems" do
        # When server rejects token request
        # Then user should get clear error message about authentication
        expect { oauth_client.live_session_token }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("401").or include("token").or include("authentication").or include("unauthorized")
        end
      end
    end
  end

  describe "session lifecycle management" do
    include_context "with mocked Faraday client"

    context "when user wants to end their session" do
      let(:response_body) { '{"result": "success"}' }

      it "properly terminates trading session" do
        # Given an authenticated session
        oauth_client.instance_variable_set(:@current_token, double("token"))
        
        # When user logs out
        result = oauth_client.logout
        
        # Then session should be cleanly terminated
        expect(result).to be true
        expect(oauth_client.authenticated?).to be false
        expect(oauth_client.token).to be_nil
      end
    end

    context "when logout encounters server issues" do
      before do
        # Set up authenticated state first
        valid_token = double("token", valid?: true)
        oauth_client.instance_variable_set(:@current_token, valid_token)
        allow(oauth_client).to receive(:authenticated?).and_return(true)
        
        # Override logout endpoint with server error
        stub_request(:post, "#{base_url}/v1/api/logout")
          .to_return(status: 500, body: "Server Error")
      end

      it "handles server errors during logout gracefully" do
        # When server has issues during logout
        # Then user should get clear error message
        expect { oauth_client.logout }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("500").or include("logout").or include("failed").or include("server")
        end
      end
    end
  end

  describe "brokerage session setup" do
    include_context "with mocked Faraday client"

    let(:session_response) { { "connected" => true, "authenticated" => true } }
    let(:response_body) { session_response.to_json }

    context "when establishing trading connection" do
      it "enables trading operations after authentication" do
        # Given user is authenticated with OAuth
        # When initializing brokerage session
        result = oauth_client.initialize_session
        
        # Then trading operations should be available
        expect(result).to eq(session_response)
        expect(result["connected"]).to be true
        expect(result["authenticated"]).to be true
      end
    end

    context "when requesting priority trading access" do
      it "provides priority access for time-sensitive trading" do
        # Given user needs urgent trading access
        # When requesting priority session
        result = oauth_client.initialize_session(priority: true)
        
        # Then priority trading should be enabled
        expect(result).to eq(session_response)
        expect(result["authenticated"]).to be true
      end
    end
  end

  describe "API communication capabilities" do
    before do
      # Ensure client is authenticated for API calls
      allow(oauth_client).to receive(:authenticated?).and_return(true)
    end

    describe "data retrieval operations" do
      it "enables account data access with proper authentication" do
        # Mock account data endpoint
        stub_request(:get, "#{base_url}/account/summary")
          .to_return(
            status: 200,
            body: '{"account_data": "portfolio_info"}',
            headers: { "Content-Type" => "application/json" }
          )

        # When authenticated user requests account information
        result = oauth_client.get("/account/summary")
        
        # Then they should receive their portfolio data
        expect(result).to be_a(Hash)
        expect(result).to have_key("account_data")
      end

      it "handles data access errors clearly" do
        # Mock server error
        stub_request(:get, "#{base_url}/account/summary")
          .to_return(status: 500, body: "Internal Server Error")
        
        # When data access fails, user should get clear error message
        expect { oauth_client.get("/account/summary") }.to raise_error(StandardError)
      end
    end

    describe "trading operations" do
      it "enables order submission with proper authentication" do
        # Mock order submission endpoint
        stub_request(:post, "#{base_url}/orders")
          .to_return(
            status: 200,
            body: '{"order_id": "12345", "status": "submitted"}',
            headers: { "Content-Type" => "application/json" }
          )

        # When authenticated user submits trading orders
        result = oauth_client.post("/orders", body: { symbol: "AAPL", quantity: 100 })
        
        # Then orders should be processed
        expect(result).to be_a(Hash)
        expect(result).to have_key("order_id")
      end

      it "handles order submission errors clearly" do
        # Mock order rejection
        stub_request(:post, "#{base_url}/orders")
          .to_return(status: 400, body: "Invalid order parameters")
        
        # When order submission fails, user should get clear error message
        expect { oauth_client.post("/orders", body: { symbol: "AAPL", quantity: 100 }) }.to raise_error(StandardError)
      end
    end
  end
end