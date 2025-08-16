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
          base_url: "https://api.ibkr.com"
        )
      )
    )
    credentials_double
  end

  before do
    # Create a fresh Rails double for each test
    rails_double = double("Rails",
      application: double("application", credentials: mock_credentials),
      logger: double("logger", error: nil, debug: nil, warn: nil)
    )
    
    stub_const("Rails", rails_double)
  end
end

RSpec.shared_context "with mocked cryptographic keys" do
  let(:mock_rsa_key) { double("RSA key") }
  let(:mock_dh_param) { double("DH param", p: double("p"), g: double("g")) }

  before do
    allow(File).to receive(:read).with("./config/certs/private_encryption.pem").and_return("mock_encryption_key")
    allow(File).to receive(:read).with("./config/certs/dhparam.pem").and_return("mock_dh_param")
    allow(File).to receive(:read).with("./config/certs/private_signature.pem").and_return("mock_signature_key")
    
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(mock_rsa_key)
    allow(OpenSSL::PKey::DH).to receive(:new).and_return(mock_dh_param)
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

RSpec.shared_context "with authenticated oauth client" do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked Faraday client"

  let(:valid_token) do
    instance_double("Ibkr::Oauth::LiveSessionToken",
      token: "valid_token",
      valid?: true,
      expired?: false
    )
  end

  let(:oauth_client) do
    client = Ibkr::Oauth.new(live: false)
    allow(client).to receive(:live_session_token).and_return(valid_token)
    allow(client).to receive(:authenticated?).and_return(true)
    client.instance_variable_set(:@token, valid_token)
    client
  end
end