# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth::Parameters do
  let(:mock_config) do
    double("config",
      consumer_key: "test_consumer_key",
      access_token: "test_access_token",
      production?: false)
  end

  let(:mock_signature_generator) do
    instance_double(Ibkr::Oauth::SignatureGenerator,
      generate_nonce: "test_nonce",
      generate_timestamp: "1234567890")
  end

  let(:builder) { described_class.new(config: mock_config, signature_generator: mock_signature_generator) }

  describe "#initialize" do
    it "sets config and signature generator" do
      expect(builder.config).to eq(mock_config)
      expect(builder.signature_generator).to eq(mock_signature_generator)
    end
  end

  describe "#reset" do
    it "clears parameters and returns self" do
      builder.add_consumer_key
      result = builder.reset
      expect(result).to eq(builder)
      expect(builder.build).to be_empty
    end
  end

  describe "#add_consumer_key" do
    it "adds consumer key to parameters" do
      builder.add_consumer_key
      expect(builder.build).to include("oauth_consumer_key" => "test_consumer_key")
    end

    it "returns self for method chaining" do
      result = builder.add_consumer_key
      expect(result).to be(builder)
    end

    it "enables fluent interface chaining" do
      result = builder.add_consumer_key.add_access_token.add_nonce
      expect(result).to be(builder)
      expect(builder.build).to include(
        "oauth_consumer_key" => "test_consumer_key",
        "oauth_token" => "test_access_token",
        "oauth_nonce" => "test_nonce"
      )
    end
  end

  describe "#add_access_token" do
    it "adds access token to parameters" do
      builder.add_access_token
      expect(builder.build).to include("oauth_token" => "test_access_token")
    end

    it "returns self for method chaining" do
      result = builder.add_access_token
      expect(result).to be(builder)
    end
  end

  describe "#add_nonce" do
    it "adds nonce to parameters" do
      builder.add_nonce
      expect(builder.build).to include("oauth_nonce" => "test_nonce")
    end

    it "returns self for method chaining" do
      result = builder.add_nonce
      expect(result).to be(builder)
    end
  end

  describe "#add_timestamp" do
    it "adds timestamp to parameters" do
      builder.add_timestamp
      expect(builder.build).to include("oauth_timestamp" => "1234567890")
    end

    it "returns self for method chaining" do
      result = builder.add_timestamp
      expect(result).to be(builder)
    end
  end

  describe "#add_realm" do
    context "in production" do
      before do
        allow(mock_config).to receive(:production?).and_return(true)
      end

      it "adds production realm" do
        builder.add_realm
        expect(builder.build).to include("realm" => "limited_poa")
      end
    end

    context "not in production" do
      it "adds test realm" do
        builder.add_realm
        expect(builder.build).to include("realm" => "test_realm")
      end
    end

    it "returns self for method chaining" do
      result = builder.add_realm
      expect(result).to be(builder)
    end
  end

  describe "#build" do
    it "returns a copy of parameters" do
      builder.add_consumer_key
      params1 = builder.build
      params2 = builder.build

      expect(params1).to eq(params2)
      expect(params1).not_to be(params2) # Different objects
    end

    it "does not allow external modification of internal state" do
      builder.add_consumer_key
      params = builder.build
      params["extra_key"] = "extra_value"

      expect(builder.build).not_to include("extra_key")
    end

    it "returns empty hash when no parameters added" do
      expect(builder.build).to eq({})
    end
  end

  describe "complex chaining scenarios" do
    it "supports long method chains" do
      result = builder
        .add_consumer_key
        .add_access_token
        .add_nonce
        .add_timestamp
        .add_realm

      expect(result).to be(builder)

      params = builder.build
      expect(params).to include(
        "oauth_consumer_key" => "test_consumer_key",
        "oauth_token" => "test_access_token",
        "oauth_nonce" => "test_nonce",
        "oauth_timestamp" => "1234567890",
        "realm" => "test_realm"
      )
    end

    it "allows reset in the middle of a chain" do
      result = builder
        .add_consumer_key
        .add_access_token
        .reset
        .add_nonce

      expect(result).to be(builder)

      params = builder.build
      expect(params).not_to include("oauth_consumer_key")
      expect(params).not_to include("oauth_token")
      expect(params).to include("oauth_nonce" => "test_nonce")
    end
  end

  describe "#initialize" do
    it "initializes with empty parameters" do
      expect(builder.build).to be_empty
    end

    it "does not share state between instances" do
      builder1 = described_class.new(config: mock_config, signature_generator: mock_signature_generator)
      builder2 = described_class.new(config: mock_config, signature_generator: mock_signature_generator)

      builder1.add_consumer_key

      expect(builder1.build).to include("oauth_consumer_key")
      expect(builder2.build).to be_empty
    end
  end

  # Test protected methods through subclass
  describe "protected methods" do
    # Create a test subclass to expose protected methods
    let(:test_builder_class) do
      Class.new(described_class) do
        def test_add_signature_method(method)
          add_signature_method(method)
        end

        def test_add_signature(signature)
          add_signature(signature)
        end
      end
    end

    let(:test_builder) { test_builder_class.new(config: mock_config, signature_generator: mock_signature_generator) }

    describe "#add_signature_method" do
      it "adds signature method to parameters" do
        test_builder.test_add_signature_method("TEST-METHOD")
        expect(test_builder.build).to include("oauth_signature_method" => "TEST-METHOD")
      end

      it "returns self for method chaining" do
        result = test_builder.test_add_signature_method("TEST-METHOD")
        expect(result).to be(test_builder)
      end
    end

    describe "#add_signature" do
      it "adds encoded signature to parameters" do
        test_builder.test_add_signature("test_signature")
        expect(test_builder.build).to include("oauth_signature" => URI.encode_www_form_component("test_signature"))
      end

      it "returns self for method chaining" do
        result = test_builder.test_add_signature("test_signature")
        expect(result).to be(test_builder)
      end

      it "properly encodes special characters" do
        test_builder.test_add_signature("special+chars=&value")
        expected = URI.encode_www_form_component("special+chars=&value")
        expect(test_builder.build["oauth_signature"]).to eq(expected)
      end
    end
  end
end

RSpec.describe Ibkr::Oauth::AuthenticationParameters do
  let(:mock_config) do
    double("config",
      consumer_key: "test_consumer_key",
      access_token: "test_access_token",
      production?: false)
  end

  let(:mock_signature_generator) do
    instance_double(Ibkr::Oauth::SignatureGenerator,
      generate_nonce: "test_nonce",
      generate_timestamp: "1234567890",
      generate_dh_challenge: "dh_challenge",
      generate_rsa_signature: "rsa_signature")
  end

  let(:builder) { described_class.new(config: mock_config, signature_generator: mock_signature_generator) }

  describe "#add_diffie_hellman_challenge" do
    it "adds DH challenge to parameters" do
      builder.add_diffie_hellman_challenge
      expect(builder.build).to include("diffie_hellman_challenge" => "dh_challenge")
    end

    it "returns self for method chaining" do
      result = builder.add_diffie_hellman_challenge
      expect(result).to be(builder)
    end
  end

  describe "#add_rsa_signature" do
    it "adds encoded RSA signature to parameters" do
      builder.add_consumer_key.add_rsa_signature
      expect(builder.build).to include("oauth_signature")
      expect(mock_signature_generator).to have_received(:generate_rsa_signature)
    end

    it "returns self for method chaining" do
      result = builder.add_rsa_signature
      expect(result).to be(builder)
    end

    it "encodes the signature properly" do
      allow(mock_signature_generator).to receive(:generate_rsa_signature).and_return("special&chars=")
      builder.add_rsa_signature
      expect(builder.build["oauth_signature"]).to eq(URI.encode_www_form_component("special&chars="))
    end
  end

  describe "#build_complete" do
    it "builds complete authentication parameters" do
      params = builder.build_complete

      expect(params).to include(
        "oauth_consumer_key" => "test_consumer_key",
        "oauth_token" => "test_access_token",
        "oauth_nonce" => "test_nonce",
        "oauth_timestamp" => "1234567890",
        "oauth_signature_method" => "RSA-SHA256",
        "diffie_hellman_challenge" => "dh_challenge",
        "oauth_signature" => URI.encode_www_form_component("rsa_signature"),
        "realm" => "test_realm"
      )
    end

    it "resets before building to ensure clean state" do
      builder.add_consumer_key
      builder.instance_variable_set(:@params, {"existing_key" => "existing_value"})

      params = builder.build_complete

      expect(params).not_to include("existing_key")
      expect(params).to include("oauth_consumer_key" => "test_consumer_key")
    end

    it "returns a new hash each time" do
      params1 = builder.build_complete
      params2 = builder.build_complete

      expect(params1).to eq(params2)
      expect(params1).not_to be(params2)
    end

    it "does not modify builder state after completion" do
      builder.build_complete
      expect(builder.build).to_not be_empty # State should remain after build_complete
    end
  end

  describe "inheritance behavior" do
    it "inherits from Parameters" do
      expect(described_class).to be < Ibkr::Oauth::Parameters
    end

    it "can use parent class methods" do
      builder.add_consumer_key
      expect(builder.build).to include("oauth_consumer_key")
    end
  end
end

RSpec.describe Ibkr::Oauth::ApiParameters do
  let(:mock_config) do
    double("config",
      consumer_key: "test_consumer_key",
      access_token: "test_access_token",
      production?: false)
  end

  let(:mock_signature_generator) do
    instance_double(Ibkr::Oauth::SignatureGenerator,
      generate_nonce: "test_nonce",
      generate_timestamp: "1234567890",
      generate_hmac_signature: "hmac_signature")
  end

  let(:request_params) do
    {
      method: "GET",
      url: "https://api.ibkr.com/test",
      query: {page: 1},
      body: {data: "test"},
      live_session_token: "live_token"
    }
  end

  let(:builder) { described_class.new(config: mock_config, signature_generator: mock_signature_generator, request_params: request_params) }

  describe "#add_hmac_signature" do
    it "adds HMAC signature with request context" do
      builder.add_consumer_key.add_access_token.add_hmac_signature

      expect(builder.build).to include("oauth_signature")
      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        hash_including(
          method: "GET",
          url: "https://api.ibkr.com/test",
          query: {page: 1},
          body: {data: "test"},
          live_session_token: "live_token"
        )
      )
    end

    it "returns self for method chaining" do
      result = builder.add_hmac_signature
      expect(result).to be(builder)
    end

    it "handles empty query and body parameters" do
      builder_with_minimal_params = described_class.new(
        config: mock_config,
        signature_generator: mock_signature_generator,
        request_params: {
          method: "GET",
          url: "https://api.ibkr.com/test",
          live_session_token: "live_token"
        }
      )

      builder_with_minimal_params.add_hmac_signature

      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        hash_including(
          query: {},
          body: {}
        )
      )
    end
  end

  describe "#build_complete" do
    it "builds complete API request parameters" do
      params = builder.build_complete

      expect(params).to include(
        "oauth_consumer_key" => "test_consumer_key",
        "oauth_token" => "test_access_token",
        "oauth_nonce" => "test_nonce",
        "oauth_timestamp" => "1234567890",
        "oauth_signature_method" => "HMAC-SHA256",
        "oauth_signature" => URI.encode_www_form_component("hmac_signature"),
        "realm" => "test_realm"
      )
    end

    it "resets before building to ensure clean state" do
      builder.instance_variable_set(:@params, {"existing_key" => "existing_value"})

      params = builder.build_complete

      expect(params).not_to include("existing_key")
      expect(params).to include("oauth_consumer_key" => "test_consumer_key")
    end

    it "uses request parameters for signature generation" do
      builder.build_complete

      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        hash_including(
          method: "GET",
          url: "https://api.ibkr.com/test",
          live_session_token: "live_token"
        )
      )
    end
  end

  describe "#initialize" do
    it "accepts request parameters" do
      expect(builder.request_params).to eq(request_params)
    end

    it "inherits from Parameters" do
      expect(described_class).to be < Ibkr::Oauth::Parameters
    end
  end
end
