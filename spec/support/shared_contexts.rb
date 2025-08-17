# frozen_string_literal: true

RSpec.shared_context "with mocked Rails credentials" do
  let(:mock_credentials) do
    credentials_double = double("credentials")
    allow(credentials_double).to receive(:dig).with(:ibkr, :oauth, :consumer_key).and_return("test_consumer_key")
    allow(credentials_double).to receive(:ibkr).and_return(
      double("ibkr",
        oauth: double("oauth",
          consumer_key: "test_consumer_key",
          access_token: "test_access_token",
          access_token_secret: Base64.encode64("test_secret"),
          base_url: "https://api.ibkr.com"))
    )
    credentials_double
  end

  before do
    # Create a fresh Rails double for each test
    rails_double = double("Rails",
      application: double("application", credentials: mock_credentials),
      logger: double("logger", error: nil, debug: nil, warn: nil))

    stub_const("Rails", rails_double)
  end
end

RSpec.shared_context "with mocked cryptographic keys" do
  let(:mock_p) { double("p", mod_exp: double("result")) }
  let(:mock_g) { double("g", mod_exp: double("result", to_s: "abcdef123456")) }
  let(:mock_rsa_key) do
    decrypted_string = "decrypted_mock_secret"
    double("RSA key",
      sign: "mock_signature_bytes",
      private_decrypt: decrypted_string)
  end
  let(:mock_dh_param) { double("DH param", p: mock_p, g: mock_g) }

  before do
    allow(File).to receive(:read).with("./config/certs/private_encryption.pem").and_return("mock_encryption_key")
    allow(File).to receive(:read).with("./config/certs/dhparam.pem").and_return("mock_dh_param")
    allow(File).to receive(:read).with("./config/certs/private_signature.pem").and_return("mock_signature_key")

    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(mock_rsa_key)
    allow(OpenSSL::PKey::DH).to receive(:new).and_return(mock_dh_param)

    # Mock Base64 operations for consistent test behavior
    allow(Base64).to receive(:strict_encode64).with("mock_signature_bytes").and_return("bW9ja19zaWduYXR1cmVfYnl0ZXM=")
    allow(Base64).to receive(:strict_encode64).with(kind_of(String)).and_return("bW9ja19lbmNvZGVkX3ZhbHVl")

    # Mock OpenSSL::BN operations for DH computations
    allow(OpenSSL::BN).to receive(:new).and_call_original
    allow(OpenSSL::BN).to receive(:new).with(kind_of(String), 16).and_return(
      double("BN", mod_exp: double("result", to_s: "computed_value", num_bits: 256))
    )

    # Mock configuration to return our mocked crypto objects
    allow_any_instance_of(Ibkr::Configuration).to receive(:encryption_key).and_return(mock_rsa_key)
    allow_any_instance_of(Ibkr::Configuration).to receive(:signature_key).and_return(mock_rsa_key)
    allow_any_instance_of(Ibkr::Configuration).to receive(:dh_params).and_return(mock_dh_param)

    # Mock signature generator methods to avoid complex crypto operations
    allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:generate_rsa_signature).and_return("mock_signature")
    allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:generate_dh_challenge).and_return("abcdef123456")
    allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:compute_live_session_token).and_return("computed_token")
    allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:decrypt_prepend).and_return("mock_prepend")

    # Mock LiveSessionToken validation to return true for test scenarios
    allow_any_instance_of(Ibkr::Oauth::LiveSessionToken).to receive(:valid?).and_return(true)
    allow_any_instance_of(Ibkr::Oauth::LiveSessionToken).to receive(:expired?).and_return(false)
  end
end

RSpec.shared_context "with mocked Faraday client" do
  let(:mock_response) { double("response", success?: true, body: response_body, headers: {}) }
  let(:mock_faraday) { double("faraday", get: mock_response, post: mock_response) }
  let(:response_body) { '{"result": "success"}' }

  before do
    allow(Faraday).to receive(:new).and_return(mock_faraday)
  end
end

RSpec.shared_context "with mocked IBKR API" do
  let(:base_url) { "https://api.ibkr.com" }

  # Make sure configuration returns the base URL we're mocking
  before do
    allow_any_instance_of(Ibkr::Configuration).to receive(:base_url).and_return(base_url)
  end
  let(:successful_auth_response) do
    {
      "diffie_hellman_response" => "abc123def456",
      "live_session_token_signature" => "valid_signature_123",
      "live_session_token_expiration" => (Time.now + 3600).to_i
    }
  end
  let(:successful_logout_response) { {"status" => "logged_out"} }
  let(:successful_session_response) { {"connected" => true, "authenticated" => true} }
  let(:successful_account_summary) do
    {
      "netliquidation" => {"amount" => 100000.0, "currency" => "USD"},
      "availablefunds" => {"amount" => 50000.0, "currency" => "USD"},
      "buyingpower" => {"amount" => 75000.0, "currency" => "USD"}
    }
  end
  let(:successful_positions_response) do
    {
      "results" => [
        {
          "conid" => "265598",
          "position" => 100,
          "description" => "APPLE INC",
          "market_value" => 15000.0,
          "currency" => "USD",
          "unrealized_pnl" => 500.0,
          "realized_pnl" => 0.0,
          "market_price" => 150.0,
          "security_type" => "STK",
          "asset_class" => "STOCK"
        }
      ]
    }
  end

  before do
    # Mock OAuth live session token endpoint
    stub_request(:post, "#{base_url}/v1/api/oauth/live_session_token")
      .to_return(
        status: 200,
        body: successful_auth_response.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock logout endpoint
    stub_request(:post, "#{base_url}/v1/api/logout")
      .to_return(
        status: 200,
        body: successful_logout_response.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock session initialization endpoint
    stub_request(:post, "#{base_url}/v1/api/iserver/auth/ssodh/init")
      .to_return(
        status: 200,
        body: successful_session_response.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock account summary endpoint
    stub_request(:get, %r{#{base_url}/v1/api/portfolio/.+/summary})
      .to_return(
        status: 200,
        body: successful_account_summary.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock positions endpoint
    stub_request(:get, %r{#{base_url}/v1/api/portfolio/.+/positions})
      .to_return(
        status: 200,
        body: successful_positions_response.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    # Mock ping/tickle endpoint
    stub_request(:post, "#{base_url}/v1/api/tickle")
      .to_return(
        status: 200,
        body: {"status" => "ok"}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end
end

RSpec.shared_context "with authenticated oauth client" do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked Faraday client"

  let(:valid_token) do
    instance_double("Ibkr::Oauth::LiveSessionToken",
      token: "valid_token",
      valid?: true,
      expired?: false)
  end

  let(:oauth_client) do
    client = Ibkr::Oauth.new(live: false)
    allow(client).to receive(:live_session_token).and_return(valid_token)
    allow(client).to receive(:authenticated?).and_return(true)
    client.instance_variable_set(:@current_token, valid_token)
    client
  end
end
