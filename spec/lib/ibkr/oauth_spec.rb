# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"

  let(:oauth_client) { described_class.new(live: false) }
  let(:live_oauth_client) { described_class.new(live: true) }

  describe "initialization" do
    context "when initializing for sandbox environment" do
      it "sets up sandbox configuration" do
        expect(oauth_client.instance_variable_get(:@_live)).to be false
      end

      it "loads required cryptographic keys" do
        expect(File).to have_received(:read).with("./config/certs/private_encryption.pem")
        expect(File).to have_received(:read).with("./config/certs/dhparam.pem")
        expect(File).to have_received(:read).with("./config/certs/private_signature.pem")
      end

      it "initializes with nil token state" do
        expect(oauth_client.token).to be_nil
      end
    end

    context "when initializing for live trading environment" do
      it "sets up live trading configuration" do
        expect(live_oauth_client.instance_variable_get(:@_live)).to be true
      end
    end
  end

  describe "#authenticate" do
    let(:mock_lst_response) do
      {
        "diffie_hellman_response" => "abcdef123456",
        "live_session_token_signature" => "signature123",
        "live_session_token_expiration" => (Time.now + 3600).to_i
      }
    end

    before do
      allow(oauth_client).to receive(:live_session_token).and_return(
        instance_double("LiveSessionToken", valid?: true)
      )
    end

    context "when authentication succeeds" do
      it "retrieves and validates a live session token" do
        # Given valid credentials and network connectivity
        # When authentication is attempted
        result = oauth_client.authenticate
        
        # Then it should successfully authenticate and set a valid token
        expect(result).to be true
        expect(oauth_client.token).not_to be_nil
      end

      it "stores the token for subsequent API requests" do
        oauth_client.authenticate
        expect(oauth_client.token).to be_instance_of(instance_double("LiveSessionToken").class)
      end
    end

    context "when authentication fails" do
      before do
        allow(oauth_client).to receive(:live_session_token).and_return(
          instance_double("LiveSessionToken", valid?: false)
        )
      end

      it "returns false for invalid credentials" do
        result = oauth_client.authenticate
        expect(result).to be false
      end
    end
  end

  describe "#live_session_token" do
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

    context "when LST request succeeds" do
      it "creates a LiveSessionToken with proper cryptographic validation" do
        # Given a successful DH key exchange response
        # When requesting a live session token
        token = oauth_client.live_session_token
        
        # Then it should create a valid token with proper signature
        expect(token).to be_instance_of(Ibkr::Oauth::LiveSessionToken)
        expect(oauth_client).to have_received(:compute_live_session_token).with(mock_dh_response)
      end

      it "handles Diffie-Hellman key exchange properly" do
        oauth_client.live_session_token
        expect(oauth_client).to have_received(:compute_live_session_token)
      end
    end

    context "when LST request fails" do
      let(:mock_response) { double("response", success?: false, status: 401, body: "Unauthorized") }

      it "raises descriptive error for authentication failures" do
        expect { oauth_client.live_session_token }.to raise_error(/Failed to get live session token: 401/)
      end
    end
  end

  describe "#logout" do
    include_context "with mocked Faraday client"

    context "when logout succeeds" do
      let(:response_body) { '{"result": "success"}' }

      it "clears the stored token and terminates the session" do
        # Given an authenticated session
        oauth_client.instance_variable_set(:@token, double("token"))
        
        # When logout is called
        result = oauth_client.logout
        
        # Then the session should be terminated and token cleared
        expect(result).to be true
        expect(oauth_client.token).to be_nil
      end
    end

    context "when logout fails" do
      let(:mock_response) { double("response", success?: false, status: 500, body: "Server Error") }

      it "raises error but preserves error information" do
        expect { oauth_client.logout }.to raise_error(/Logout failed: 500/)
      end
    end
  end

  describe "#initialize_session" do
    include_context "with mocked Faraday client"

    let(:session_response) { { "connected" => true, "authenticated" => true } }
    let(:response_body) { session_response.to_json }

    context "when initializing regular session" do
      it "establishes brokerage connection without priority" do
        # Given an authenticated OAuth client
        # When initializing a session without priority
        result = oauth_client.initialize_session
        
        # Then it should establish a regular brokerage session
        expect(result).to eq(session_response)
        expect(oauth_client).to have_received(:post).with(
          "/v1/api/iserver/auth/ssodh/init",
          body: { publish: true, compete: false }
        )
      end
    end

    context "when requesting priority session" do
      it "requests priority access for urgent trading operations" do
        oauth_client.initialize_session(priority: true)
        
        expect(oauth_client).to have_received(:post).with(
          "/v1/api/iserver/auth/ssodh/init", 
          body: { publish: true, compete: true }
        )
      end
    end
  end

  describe "HTTP client delegation" do
    include_context "with mocked Faraday client"

    let(:response_body) { '{"test": "data"}' }

    describe "#get" do
      it "delegates GET requests with automatic JSON parsing" do
        result = oauth_client.get("/test/endpoint")
        expect(result).to eq({ "test" => "data" })
      end

      it "handles gzip-compressed responses" do
        compressed_body = StringIO.new
        Zlib::GzipWriter.wrap(compressed_body) { |gz| gz.write(response_body) }
        
        allow(mock_response).to receive(:headers).and_return("content-encoding" => "gzip")
        allow(mock_response).to receive(:body).and_return(compressed_body.string)
        
        result = oauth_client.get("/test/endpoint")
        expect(result).to eq({ "test" => "data" })
      end

      include_examples "a failed API request", "GET request failed"
    end

    describe "#post" do
      it "delegates POST requests with JSON body encoding" do
        result = oauth_client.post("/test/endpoint", body: { "key" => "value" })
        expect(result).to eq({ "test" => "data" })
      end

      include_examples "a failed API request", "POST request failed"
    end
  end
end