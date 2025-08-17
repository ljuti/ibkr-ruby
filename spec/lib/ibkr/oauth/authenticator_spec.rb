# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth::Authenticator do
  let(:mock_config) do
    double("config",
      consumer_key: "test_consumer_key",
      access_token: "test_access_token",
      base_url: "https://api.ibkr.com",
      signature_key: double("signature_key"),
      encryption_key: double("encryption_key"),
      access_token_secret: "test_secret",
      dh_params: double("dh_params"),
      production?: false)
  end

  let(:mock_http_client) { double("http_client") }
  let(:mock_signature_generator) { instance_double(Ibkr::Oauth::SignatureGenerator) }
  let(:authenticator) { described_class.new(config: mock_config, http_client: mock_http_client) }

  before do
    allow(Ibkr::Oauth::SignatureGenerator).to receive(:new).with(mock_config).and_return(mock_signature_generator)
  end

  describe "#initialize" do
    it "sets up config and http client" do
      expect(authenticator.config).to eq(mock_config)
      expect(authenticator.http_client).to eq(mock_http_client)
    end

    it "creates a signature generator" do
      new_authenticator = described_class.new(config: mock_config, http_client: mock_http_client)
      expect(new_authenticator.signature_generator).to eq(mock_signature_generator)
    end

    it "initializes current_token as nil" do
      expect(authenticator.current_token).to be_nil
    end
  end

  describe "#authenticate" do
    context "when authentication succeeds with a valid token" do
      let(:valid_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken,
          token: "valid_token_string",
          valid?: true)
      end

      before do
        allow(authenticator).to receive(:request_live_session_token).and_return(valid_token)
      end

      it "returns true when the token is valid" do
        result = authenticator.authenticate
        expect(result).to be true
      end

      it "stores the token for future use" do
        authenticator.authenticate
        expect(authenticator.current_token).to eq(valid_token)
      end

      it "validates the token with the consumer key" do
        expect(valid_token).to receive(:valid?).with(mock_config.consumer_key)
        authenticator.authenticate
      end
    end

    context "when authentication succeeds but token is invalid" do
      let(:invalid_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken,
          token: "invalid_token_string",
          valid?: false)
      end

      before do
        allow(authenticator).to receive(:request_live_session_token).and_return(invalid_token)
      end

      it "returns false when the token is invalid" do
        result = authenticator.authenticate
        expect(result).to be false
      end

      it "still stores the token even if invalid" do
        authenticator.authenticate
        expect(authenticator.current_token).to eq(invalid_token)
      end

      it "validates the token with the consumer key" do
        expect(invalid_token).to receive(:valid?).with(mock_config.consumer_key)
        authenticator.authenticate
      end
    end

    context "when authentication fails" do
      it "raises an error when request_live_session_token fails" do
        allow(authenticator).to receive(:request_live_session_token)
          .and_raise(Ibkr::AuthenticationError, "Authentication failed")

        expect { authenticator.authenticate }
          .to raise_error(Ibkr::AuthenticationError, "Authentication failed")
      end
    end
  end

  describe "#authenticated?" do
    context "when no token exists" do
      it "returns false" do
        expect(authenticator.authenticated?).to be false
      end
    end

    context "when a valid token exists" do
      let(:valid_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true)
      end

      before do
        authenticator.current_token = valid_token
      end

      it "returns true" do
        expect(authenticator.authenticated?).to be true
      end

      it "checks token validity with consumer key" do
        expect(valid_token).to receive(:valid?).with(mock_config.consumer_key)
        authenticator.authenticated?
      end
    end

    context "when an invalid token exists" do
      let(:invalid_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken, valid?: false)
      end

      before do
        authenticator.current_token = invalid_token
      end

      it "returns false" do
        expect(authenticator.authenticated?).to be false
      end
    end

    context "when token is nil" do
      it "returns false without error" do
        authenticator.current_token = nil
        expect(authenticator.authenticated?).to be false
      end
    end
  end

  describe "#token" do
    context "when token needs refreshing" do
      let(:old_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken,
          valid?: false,
          expired?: true)
      end

      let(:new_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken,
          valid?: true,
          expired?: false)
      end

      before do
        authenticator.current_token = old_token
        allow(authenticator).to receive(:refresh_token_if_needed).and_call_original
        allow(authenticator).to receive(:request_live_session_token).and_return(new_token)
      end

      it "refreshes the token when needed" do
        expect(authenticator).to receive(:refresh_token_if_needed)
        authenticator.token
      end

      it "returns the current token" do
        result = authenticator.token
        expect(result).to eq(new_token)
      end
    end

    context "when token is still valid" do
      let(:valid_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken,
          valid?: true,
          expired?: false)
      end

      before do
        authenticator.current_token = valid_token
        allow(authenticator).to receive(:refresh_token_if_needed).and_call_original
      end

      it "returns the existing token without refreshing" do
        expect(authenticator).not_to receive(:request_live_session_token)
        result = authenticator.token
        expect(result).to eq(valid_token)
      end
    end

    context "when no token exists" do
      it "refreshes and returns new token" do
        new_token = instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true, expired?: false)
        allow(authenticator).to receive(:request_live_session_token).and_return(new_token)
        
        result = authenticator.token
        expect(result).to eq(new_token)
      end
    end
  end

  describe "#logout" do
    context "when authenticated" do
      let(:valid_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true)
      end

      let(:successful_response) do
        double("response", success?: true, body: {}.to_json)
      end

      before do
        authenticator.current_token = valid_token
        allow(mock_http_client).to receive(:post_raw).with("/v1/api/logout").and_return(successful_response)
      end

      it "calls the logout endpoint" do
        expect(mock_http_client).to receive(:post_raw).with("/v1/api/logout")
        authenticator.logout
      end

      it "clears the current token" do
        authenticator.logout
        expect(authenticator.current_token).to be_nil
      end

      it "returns true on successful logout" do
        result = authenticator.logout
        expect(result).to be true
      end
    end

    context "when not authenticated" do
      it "returns true without making API call" do
        expect(mock_http_client).not_to receive(:post_raw)
        result = authenticator.logout
        expect(result).to be true
      end
    end

    context "when logout fails" do
      let(:valid_token) do
        instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true)
      end

      let(:failed_response) do
        double("response", success?: false, status: 500, body: "Server error")
      end

      before do
        authenticator.current_token = valid_token
        allow(mock_http_client).to receive(:post_raw).with("/v1/api/logout").and_return(failed_response)
      end

      it "raises an error" do
        expect { authenticator.logout }
          .to raise_error(Ibkr::ApiError)
      end

      it "does not clear the token on failure" do
        expect { authenticator.logout }.to raise_error(Ibkr::ApiError)
        expect(authenticator.current_token).to eq(valid_token)
      end
    end
  end

  describe "#initialize_session" do
    let(:valid_token) { instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true) }
    
    context "when authenticated" do
      before do
        authenticator.current_token = valid_token
      end

      context "with successful response" do
        let(:success_response) do
          double("response", success?: true, body: '{"session": "initialized"}')
        end

        it "initializes session with default priority" do
          expect(mock_http_client).to receive(:post_raw)
            .with("/v1/api/iserver/auth/ssodh/init", body: {publish: true, compete: false})
            .and_return(success_response)
          
          result = authenticator.initialize_session
          expect(result).to eq({"session" => "initialized"})
        end

        it "initializes session with high priority when specified" do
          expect(mock_http_client).to receive(:post_raw)
            .with("/v1/api/iserver/auth/ssodh/init", body: {publish: true, compete: true})
            .and_return(success_response)
          
          result = authenticator.initialize_session(priority: true)
          expect(result).to eq({"session" => "initialized"})
        end
      end

      context "with failed response" do
        let(:failed_response) do
          double("response", success?: false, status: 401, body: "Unauthorized")
        end

        it "raises SessionInitializationFailed error" do
          allow(mock_http_client).to receive(:post_raw).and_return(failed_response)
          
          expect { authenticator.initialize_session }
            .to raise_error(Ibkr::AuthenticationError)
        end
      end
    end

    context "when not authenticated" do
      it "raises AuthenticationError" do
        expect { authenticator.initialize_session }
          .to raise_error(Ibkr::AuthenticationError, "Not authenticated. Call authenticate first.")
      end
    end
  end

  describe "#ping" do
    let(:valid_token) { instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true) }
    
    context "when authenticated" do
      before do
        authenticator.current_token = valid_token
      end

      context "with successful response" do
        let(:success_response) do
          double("response", success?: true, body: '{"ssoExpires": 120, "collission": false}')
        end

        it "sends ping request and returns parsed response" do
          expect(mock_http_client).to receive(:post_raw)
            .with("/v1/api/tickle")
            .and_return(success_response)
          
          result = authenticator.ping
          expect(result).to eq({"ssoExpires" => 120, "collission" => false})
        end
      end

      context "with failed response" do
        let(:failed_response) do
          double("response", success?: false, status: 500, body: "Internal Server Error")
        end

        it "raises ApiError with ping failed message" do
          allow(mock_http_client).to receive(:post_raw).and_return(failed_response)
          
          expect { authenticator.ping }
            .to raise_error(Ibkr::ApiError) do |error|
              expect(error.message).to include("Ping failed")
            end
        end
      end
    end

    context "when not authenticated" do
      it "raises AuthenticationError" do
        expect { authenticator.ping }
          .to raise_error(Ibkr::AuthenticationError, "Not authenticated. Call authenticate first.")
      end
    end
  end

  describe "#oauth_header_for_authentication" do
    before do
      allow(mock_signature_generator).to receive(:generate_dh_challenge).and_return("dh_challenge_value")
      allow(mock_signature_generator).to receive(:generate_nonce).and_return("nonce123")
      allow(mock_signature_generator).to receive(:generate_timestamp).and_return("1234567890")
      allow(mock_signature_generator).to receive(:generate_rsa_signature).and_return("rsa_signature")
    end

    it "builds and formats OAuth header for authentication" do
      header = authenticator.oauth_header_for_authentication
      
      expect(header).to include('oauth_consumer_key="test_consumer_key"')
      expect(header).to include('oauth_token="test_access_token"')
      expect(header).to include('oauth_nonce="nonce123"')
      expect(header).to include('oauth_timestamp="1234567890"')
      expect(header).to include('oauth_signature_method="RSA-SHA256"')
      expect(header).to include('diffie_hellman_challenge="dh_challenge_value"')
      expect(header).to include('oauth_signature=')
      expect(header).to include('realm="test_realm"')
    end

    it "generates unique nonce and timestamp for each call" do
      expect(mock_signature_generator).to receive(:generate_nonce).twice.and_return("nonce1", "nonce2")
      expect(mock_signature_generator).to receive(:generate_timestamp).twice.and_return("time1", "time2")
      
      header1 = authenticator.oauth_header_for_authentication
      header2 = authenticator.oauth_header_for_authentication
      
      expect(header1).not_to eq(header2)
    end

    context "when in production" do
      before do
        allow(mock_config).to receive(:production?).and_return(true)
      end

      it "uses production realm" do
        header = authenticator.oauth_header_for_authentication
        expect(header).to include('realm="limited_poa"')
      end
    end
  end

  describe "#oauth_header_for_api_request" do
    let(:valid_token) do
      instance_double(Ibkr::Oauth::LiveSessionToken,
        valid?: true,
        token: "live_session_token_value")
    end

    context "when authenticated" do
      before do
        authenticator.current_token = valid_token
        allow(mock_signature_generator).to receive(:generate_nonce).and_return("api_nonce")
        allow(mock_signature_generator).to receive(:generate_timestamp).and_return("api_timestamp")
        allow(mock_signature_generator).to receive(:generate_hmac_signature).and_return("hmac_signature")
      end

      it "builds OAuth header with HMAC signature" do
        header = authenticator.oauth_header_for_api_request(
          method: "GET",
          url: "https://api.ibkr.com/v1/api/accounts"
        )
        
        expect(header).to include('oauth_signature_method="HMAC-SHA256"')
        expect(header).to include('oauth_signature="hmac_signature"')
      end

      it "passes query and body parameters to signature generator" do
        query = {page: 1}
        body = {data: "test"}
        
        expect(mock_signature_generator).to receive(:generate_hmac_signature).with(
          hash_including(
            method: "POST",
            url: "https://api.ibkr.com/test",
            query: query,
            body: body,
            live_session_token: "live_session_token_value"
          )
        )
        
        authenticator.oauth_header_for_api_request(
          method: "POST",
          url: "https://api.ibkr.com/test",
          query: query,
          body: body
        )
      end
    end

    context "when not authenticated" do
      it "raises AuthenticationError" do
        expect { 
          authenticator.oauth_header_for_api_request(
            method: "GET",
            url: "https://api.ibkr.com/test"
          )
        }.to raise_error(Ibkr::AuthenticationError, "Not authenticated. Call authenticate first.")
      end
    end
  end

  describe "#live_session_token" do
    it "delegates to #token" do
      valid_token = instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true, expired?: false)
      authenticator.current_token = valid_token
      allow(authenticator).to receive(:refresh_token_if_needed)
      
      expect(authenticator.live_session_token).to eq(authenticator.token)
    end
  end

  describe "private methods" do
    describe "#request_live_session_token" do
      let(:dh_response) { "dh_response_value" }
      let(:signature) { "token_signature" }
      let(:expiration) { "1234567890" }
      
      context "with successful response" do
        let(:success_response) do
          double("response",
            success?: true,
            body: {
              diffie_hellman_response: dh_response,
              live_session_token_signature: signature,
              live_session_token_expiration: expiration
            }.to_json)
        end

        before do
          allow(mock_http_client).to receive(:post_raw)
            .with("/v1/api/oauth/live_session_token")
            .and_return(success_response)
          allow(mock_signature_generator).to receive(:compute_live_session_token)
            .with(dh_response)
            .and_return("computed_token")
        end

        it "requests and parses live session token" do
          token = authenticator.send(:request_live_session_token)
          
          expect(token).to be_a(Ibkr::Oauth::LiveSessionToken)
          expect(mock_signature_generator).to have_received(:compute_live_session_token).with(dh_response)
        end
      end

      context "with failed response" do
        let(:failed_response) do
          double("response", success?: false, status: 401, body: "Unauthorized")
        end

        it "raises AuthenticationError" do
          allow(mock_http_client).to receive(:post_raw).and_return(failed_response)
          
          expect { authenticator.send(:request_live_session_token) }
            .to raise_error(Ibkr::AuthenticationError)
        end
      end

      context "with invalid JSON response" do
        let(:invalid_response) do
          double("response", success?: true, body: "not json")
        end

        it "raises AuthenticationError with parse error message" do
          allow(mock_http_client).to receive(:post_raw).and_return(invalid_response)
          
          expect { authenticator.send(:request_live_session_token) }
            .to raise_error(Ibkr::AuthenticationError, /Invalid response format/)
        end
      end

      context "with missing required fields" do
        let(:incomplete_response) do
          double("response", success?: true, body: {some_field: "value"}.to_json)
        end

        it "creates a LiveSessionToken with nil values when fields are missing" do
          allow(mock_http_client).to receive(:post_raw).and_return(incomplete_response)
          allow(mock_signature_generator).to receive(:compute_live_session_token).and_return("computed_token")
          
          # When fields are missing, LiveSessionToken.new will be called with nil values
          token = authenticator.send(:request_live_session_token)
          expect(token).to be_a(Ibkr::Oauth::LiveSessionToken)
          expect(token.signature).to be_nil
          expect(token.expires_in).to be_nil
        end
      end
    end

    describe "#ensure_authenticated!" do
      context "when authenticated" do
        let(:valid_token) { instance_double(Ibkr::Oauth::LiveSessionToken, valid?: true) }
        
        it "does not raise error" do
          authenticator.current_token = valid_token
          expect { authenticator.send(:ensure_authenticated!) }.not_to raise_error
        end
      end

      context "when not authenticated" do
        it "raises AuthenticationError with helpful message" do
          expect { authenticator.send(:ensure_authenticated!) }
            .to raise_error(Ibkr::AuthenticationError, "Not authenticated. Call authenticate first.")
        end
      end
    end

    describe "#refresh_token_if_needed" do
      context "when token is nil" do
        it "calls authenticate" do
          expect(authenticator).to receive(:authenticate)
          authenticator.send(:refresh_token_if_needed)
        end
      end

      context "when token is expired" do
        let(:expired_token) do
          instance_double(Ibkr::Oauth::LiveSessionToken, expired?: true)
        end

        it "calls authenticate" do
          authenticator.current_token = expired_token
          expect(authenticator).to receive(:authenticate)
          authenticator.send(:refresh_token_if_needed)
        end
      end

      context "when token is valid and not expired" do
        let(:valid_token) do
          instance_double(Ibkr::Oauth::LiveSessionToken, expired?: false)
        end

        it "does not call authenticate" do
          authenticator.current_token = valid_token
          expect(authenticator).not_to receive(:authenticate)
          authenticator.send(:refresh_token_if_needed)
        end
      end
    end

    describe "#format_oauth_header" do
      it "formats params as OAuth header string" do
        params = {
          "oauth_consumer_key" => "key123",
          "oauth_nonce" => "nonce456",
          "realm" => "test"
        }
        
        header = authenticator.send(:format_oauth_header, params)
        
        expect(header).to eq('oauth_consumer_key="key123", oauth_nonce="nonce456", realm="test"')
      end

      it "sorts parameters alphabetically" do
        params = {
          "z_param" => "last",
          "a_param" => "first",
          "m_param" => "middle"
        }
        
        header = authenticator.send(:format_oauth_header, params)
        
        expect(header).to eq('a_param="first", m_param="middle", z_param="last"')
      end
    end

    describe "#realm" do
      context "in production" do
        it "returns limited_poa" do
          allow(mock_config).to receive(:production?).and_return(true)
          expect(authenticator.send(:realm)).to eq("limited_poa")
        end
      end

      context "not in production" do
        it "returns test_realm" do
          allow(mock_config).to receive(:production?).and_return(false)
          expect(authenticator.send(:realm)).to eq("test_realm")
        end
      end
    end
  end
end