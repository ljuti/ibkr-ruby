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
        expect(oauth_client.live).to be false
      end

      it "initializes in unauthenticated state" do
        # When client is first created
        # Then user starts in unauthenticated state
        authenticator = oauth_client.authenticator
        expect(authenticator.current_token).to be_nil
        expect(oauth_client.authenticated?).to be false
      end
    end

    context "when setting up for live trading environment" do
      it "provides production trading environment" do
        # When user creates client for live trading
        # Then it should be configured for real trading
        expect(live_oauth_client.live).to be true
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
        # Override the successful auth mock with an error response
        stub_request(:post, "#{base_url}/v1/api/oauth/live_session_token")
          .to_return(
            status: 401,
            body: '{"error": "invalid_credentials"}',
            headers: {"Content-Type" => "application/json"}
          )
      end

      it "clearly indicates authentication failure" do
        # Given user has invalid IBKR credentials
        # When they attempt to authenticate
        # Then authentication should fail clearly with an error
        expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("credential").or include("unauthorized").or include("authentication")
        end

        # And user should not be authenticated
        expect(oauth_client.authenticated?).to be false
      end
    end
  end

  describe "session token management" do
    # Remove Faraday mocking - we use WebMock for HTTP requests
    let(:mock_dh_response) { "fedcba654321" }
    let(:mock_signature) { "valid_signature" }
    let(:mock_expiration) { (Time.now + 3600).to_i }

    before do
      # Mock the signature generator to avoid complex crypto operations
      allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:compute_live_session_token).and_return("computed_token")
    end

    context "when token request succeeds" do
      before do
        # Ensure we start with no existing token to test fresh token generation
        oauth_client.authenticator.current_token = nil
      end

      it "provides valid session token for trading operations" do
        # Given successful server response (mocked by WebMock)
        # When requesting session token
        token = oauth_client.live_session_token

        # Then user should receive valid token for trading
        expect(token).to be_instance_of(Ibkr::Oauth::LiveSessionToken)
        expect(token.valid?).to be true
      end

      it "enables secure communication with IBKR servers" do
        # When session token is obtained (mocked by WebMock)
        # Then it should enable secure API communication
        token = oauth_client.live_session_token
        expect(token).not_to be_nil
        expect(token).to be_instance_of(Ibkr::Oauth::LiveSessionToken)
      end
    end

    context "when token becomes invalid" do
      it "handles invalid token scenarios gracefully" do
        # Given an invalid token in the authenticator
        invalid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "invalid_token",
          valid?: false,
          expired?: true)

        # Set up the authenticator state directly
        authenticator = oauth_client.authenticator
        authenticator.current_token = invalid_token

        # When checking authentication with invalid token
        # Then user should know they need to re-authenticate
        expect(oauth_client.authenticated?).to be false

        # And requesting a new token should work via refresh mechanism
        # (this will trigger a new token request via our mocked HTTP endpoints)
        new_token = oauth_client.live_session_token
        expect(new_token).to be_instance_of(Ibkr::Oauth::LiveSessionToken)
      end
    end
  end

  describe "session lifecycle management" do
    context "when user wants to end their session" do
      it "properly terminates trading session" do
        # Given an authenticated session
        valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "valid_token",
          valid?: true,
          expired?: false)

        # Set up authenticator state directly
        authenticator = oauth_client.authenticator
        authenticator.current_token = valid_token

        # When user logs out (logout endpoint mocked by WebMock)
        result = oauth_client.logout

        # Then session should be cleanly terminated
        expect(result).to be true
        expect(oauth_client.authenticated?).to be false
        expect(authenticator.current_token).to be_nil
      end
    end

    context "when logout encounters server issues" do
      before do
        # Set up authenticated state first
        valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "valid_token",
          valid?: true,
          expired?: false)

        # Set up authenticator state directly
        authenticator = oauth_client.authenticator
        authenticator.current_token = valid_token

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
    let(:session_response) { {"connected" => true, "authenticated" => true} }

    before do
      # Set up authenticated state for session initialization
      valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
        token: "valid_token",
        valid?: true,
        expired?: false)

      # Set up authenticator state directly
      authenticator = oauth_client.authenticator
      authenticator.current_token = valid_token
    end

    context "when establishing trading connection" do
      it "enables trading operations after authentication" do
        # Given user is authenticated with OAuth
        # When initializing brokerage session (endpoint mocked by WebMock)
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
        # When requesting priority session (endpoint mocked by WebMock)
        result = oauth_client.initialize_session(priority: true)

        # Then priority trading should be enabled
        expect(result).to eq(session_response)
        expect(result["authenticated"]).to be true
      end
    end
  end

  describe "API communication capabilities" do
    before do
      # Set up authenticated state for API calls
      valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
        token: "valid_token",
        valid?: true,
        expired?: false)

      # Set up authenticator state directly
      authenticator = oauth_client.authenticator
      authenticator.current_token = valid_token
    end

    describe "data retrieval operations" do
      it "enables account data access with proper authentication" do
        # Mock account data endpoint
        stub_request(:get, "#{base_url}/account/summary")
          .to_return(
            status: 200,
            body: '{"account_data": "portfolio_info"}',
            headers: {"Content-Type" => "application/json"}
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
            headers: {"Content-Type" => "application/json"}
          )

        # When authenticated user submits trading orders
        result = oauth_client.post("/orders", body: {symbol: "AAPL", quantity: 100})

        # Then orders should be processed
        expect(result).to be_a(Hash)
        expect(result).to have_key("order_id")
      end

      it "handles order submission errors clearly" do
        # Mock order rejection
        stub_request(:post, "#{base_url}/orders")
          .to_return(status: 400, body: "Invalid order parameters")

        # When order submission fails, user should get clear error message
        expect { oauth_client.post("/orders", body: {symbol: "AAPL", quantity: 100}) }.to raise_error(StandardError)
      end
    end
  end
end
