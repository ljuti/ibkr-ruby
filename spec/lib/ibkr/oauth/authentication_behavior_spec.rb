# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OAuth Authentication Behavior" do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked Faraday client"

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

      before do
        # Create a mock valid token that validates with any consumer key
        mock_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "computed_token",
          expired?: false
        )
        allow(mock_token).to receive(:valid?).with(any_args).and_return(true)
        
        # Mock the live_session_token method to return our mock token
        allow(oauth_client).to receive(:live_session_token).and_return(mock_token)
      end

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
        result = oauth_client.authenticate
        
        # When user attempts authentication for trading access
        # Then they should gain access to trading operations
        expect(oauth_client.authenticated?).to be(true), "User should be authenticated and ready for trading operations"
        
        # And trading session should be properly established
        expect(oauth_client.token).not_to be_nil, "User should have session token enabling API trading requests"
      end
    end

    context "when user provides invalid credentials" do
      before do
        mock_response = double("response", 
          success?: false, 
          status: 401, 
          body: '{"error": "invalid_credentials"}',
          headers: {}
        )
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(mock_response)
      end

      it "clearly indicates authentication failure" do
        # When user provides invalid credentials
        # Then authentication should fail with clear error
        expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("credential").or include("unauthorized").or include("authentication")
        end
        
        # And user should not be authenticated
        expect(oauth_client.authenticated?).to be false
        expect(oauth_client.token).to be_nil
      end
    end

    context "when session management is needed" do
      before do
        # Simulate successful authentication
        valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "valid_token",
          valid?: true,
          expired?: false
        )
        oauth_client.instance_variable_set(:@current_token, valid_token)
      end

      it "allows user to logout and clear session" do
        # Given an authenticated session
        expect(oauth_client.authenticated?).to be true
        
        # When user logs out
        mock_response = double("response", success?: true, body: '{"status": "logged_out"}')
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(mock_response)
        
        result = oauth_client.logout
        
        # Then session should be terminated
        expect(result).to be true
        expect(oauth_client.authenticated?).to be false
        expect(oauth_client.token).to be_nil
      end

      it "enables brokerage session initialization for trading" do
        # Given an authenticated session
        expect(oauth_client.authenticated?).to be true
        
        # When user initializes brokerage session
        mock_response = double("response", 
          success?: true, 
          body: '{"authenticated": true, "connected": true}'
        )
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(mock_response)
        
        result = oauth_client.initialize_session
        
        # Then brokerage session should be ready for trading
        expect(result).to be_a(Hash)
        expect(result).to have_key("authenticated")
      end
    end
  end

  describe "Token lifecycle management" do
    it "handles token expiration gracefully" do
      # Given an expired token
      expired_token = instance_double("Ibkr::Oauth::LiveSessionToken",
        token: "expired_token",
        valid?: false,
        expired?: true
      )
      oauth_client.instance_variable_set(:@current_token, expired_token)
      
      # When checking authentication status
      # Then user should know token is expired
      expect(oauth_client.authenticated?).to be false
      expect(oauth_client.token.expired?).to be true
    end

    it "provides valid tokens to authenticated users" do
      # Given a valid token
      valid_token = instance_double("Ibkr::Oauth::LiveSessionToken",
        token: "valid_token",
        valid?: true,
        expired?: false
      )
      oauth_client.instance_variable_set(:@current_token, valid_token)
      
      # When user accesses token
      # Then they should have a valid session
      expect(oauth_client.authenticated?).to be true
      expect(oauth_client.token.valid?).to be true
    end
  end

  describe "Error scenarios from user perspective" do
    it "handles network connectivity issues" do
      # When network is unavailable
      allow_any_instance_of(Faraday::Connection).to receive(:post).and_raise(Faraday::ConnectionFailed, "Network error")
      
      # Then user should get clear error about connectivity
      expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
        expect(error.message).to include("Network error")
      end
    end

    it "handles server maintenance scenarios" do
      # When IBKR servers are down
      mock_response = double("response", 
        success?: false, 
        status: 503, 
        body: '{"error": "service_unavailable"}',
        headers: {}
      )
      allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(mock_response)
      
      # Then user should understand it's a temporary issue
      expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
        expect(error.message.downcase).to include("unavailable").or include("service").or include("maintenance")
      end
    end
  end
end