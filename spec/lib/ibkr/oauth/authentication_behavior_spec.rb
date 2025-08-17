# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OAuth Authentication Behavior" do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked IBKR API"

  let(:oauth_client) { Ibkr::Oauth.new(live: false) }

  describe "Authentication workflow from user perspective" do
    context "when user has valid credentials and certificates" do
      let(:successful_lst_response) do
        {
          "diffie_hellman_response" => "abc123",
          "live_session_token_signature" => "valid_signature",
          "live_session_token_expiration" => (Time.now + 3600).to_i
        }
      end

      # No additional setup needed - WebMock handles the HTTP responses

      it "successfully authenticates and provides access to trading operations" do
        # When user authenticates with valid credentials
        result = oauth_client.authenticate

        # Then authentication should succeed, giving user access to trading
        expect(result).to be(true), "Authentication should succeed with valid credentials, but user got access denied"

        # And user should have secure access for trading operations
        expect(oauth_client.authenticated?).to be(true), "User should be in authenticated state for trading operations"
        expect(oauth_client.token).not_to be_nil, "User should have session token for API access"
      end

      it "enables trading operations after successful authentication" do
        oauth_client.authenticate

        # When user attempts authentication for trading access
        # Then they should gain access to trading operations
        expect(oauth_client.authenticated?).to be(true), "User should be authenticated and ready for trading operations"

        # And trading session should be properly established
        expect(oauth_client.token).not_to be_nil, "User should have session token enabling API trading requests"
      end
    end

    context "when user provides invalid credentials" do
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
        # When user provides invalid credentials
        # Then authentication should fail with clear error
        expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("credential").or include("unauthorized").or include("authentication")
        end

        # And user should not be authenticated
        expect(oauth_client.authenticated?).to be false
      end
    end

    context "when session management is needed" do
      before do
        # Simulate successful authentication by setting up authenticator state
        valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "valid_token",
          valid?: true,
          expired?: false)

        # Set up the authenticator state directly
        authenticator = oauth_client.authenticator
        authenticator.current_token = valid_token
      end

      it "allows user to logout and clear session" do
        # Given an authenticated session
        expect(oauth_client.authenticated?).to be true

        # When user logs out (already mocked by "with mocked IBKR API")

        result = oauth_client.logout

        # Then session should be terminated
        expect(result).to be true
        expect(oauth_client.authenticated?).to be false

        # Check that token was cleared from authenticator
        authenticator = oauth_client.authenticator
        expect(authenticator.current_token).to be_nil
      end

      it "enables brokerage session initialization for trading" do
        # Given an authenticated session
        expect(oauth_client.authenticated?).to be true

        # When user initializes brokerage session (already mocked by "with mocked IBKR API")

        result = oauth_client.initialize_session

        # Then brokerage session should be ready for trading
        expect(result).to be_a(Hash)
        expect(result).to have_key("connected")
        expect(result["connected"]).to be true
      end
    end
  end

  describe "Token lifecycle management" do
    it "handles token expiration gracefully" do
      # Given an expired token
      expired_token = instance_double("Ibkr::Oauth::LiveSessionToken",
        token: "expired_token",
        valid?: false,
        expired?: true)

      # Set up the authenticator state directly
      authenticator = oauth_client.authenticator
      authenticator.current_token = expired_token

      # When checking authentication status
      # Then user should know token is expired
      expect(oauth_client.authenticated?).to be false

      # Access token directly from authenticator to check expiry
      current_token = authenticator.current_token
      expect(current_token.expired?).to be true
    end

    it "provides valid tokens to authenticated users" do
      # Given a valid token
      valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
        token: "valid_token",
        valid?: true,
        expired?: false)

      # Set up the authenticator state directly
      authenticator = oauth_client.authenticator
      authenticator.current_token = valid_token

      # When user accesses token
      # Then they should have a valid session
      expect(oauth_client.authenticated?).to be true
      expect(oauth_client.token.valid?).to be true
    end
  end

  describe "Error scenarios from user perspective" do
    it "handles network connectivity issues" do
      # When network is unavailable
      stub_request(:post, "#{base_url}/v1/api/oauth/live_session_token").to_raise(Faraday::ConnectionFailed.new("Network error"))

      # Then user should get clear error about connectivity
      expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
        expect(error.message).to include("Network error")
      end
    end

    it "handles server maintenance scenarios" do
      # When IBKR servers are down
      stub_request(:post, "#{base_url}/v1/api/oauth/live_session_token")
        .to_return(
          status: 503,
          body: '{"error": "service_unavailable"}',
          headers: {"Content-Type" => "application/json"}
        )

      # Then user should understand it's a temporary issue
      expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
        expect(error.message.downcase).to include("unavailable").or include("service").or include("maintenance").or include("503")
      end
    end
  end
end
