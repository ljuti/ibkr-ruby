# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth::Signature do
  let(:mock_signature_generator) { instance_double(Ibkr::Oauth::SignatureGenerator) }
  let(:strategy) { described_class.new(mock_signature_generator) }

  describe "#initialize" do
    it "sets signature generator" do
      expect(strategy.signature_generator).to eq(mock_signature_generator)
    end
  end

  describe "#generate_signature" do
    it "raises NotImplementedError" do
      expect { strategy.generate_signature({}) }
        .to raise_error(NotImplementedError, "Subclasses must implement #generate_signature")
    end
  end

  describe "#signature_method" do
    it "raises NotImplementedError" do
      expect { strategy.signature_method }
        .to raise_error(NotImplementedError, "Subclasses must implement #signature_method")
    end
  end
end

RSpec.describe Ibkr::Oauth::RsaSignature do
  let(:mock_signature_generator) do
    instance_double(Ibkr::Oauth::SignatureGenerator,
      generate_rsa_signature: "rsa_signature")
  end

  let(:strategy) { described_class.new(mock_signature_generator) }

  describe "#initialize" do
    it "inherits from Signature" do
      expect(described_class).to be < Ibkr::Oauth::Signature
    end

    it "sets signature generator through parent class" do
      expect(strategy.signature_generator).to eq(mock_signature_generator)
    end
  end

  describe "#generate_signature" do
    it "delegates to signature generator's RSA method" do
      params = {"oauth_consumer_key" => "key"}
      result = strategy.generate_signature(params)

      expect(result).to eq("rsa_signature")
      expect(mock_signature_generator).to have_received(:generate_rsa_signature).with(params)
    end
  end

  describe "#signature_method" do
    it "returns RSA-SHA256" do
      expect(strategy.signature_method).to eq("RSA-SHA256")
    end
  end
end

RSpec.describe Ibkr::Oauth::HmacSignature do
  let(:mock_signature_generator) do
    instance_double(Ibkr::Oauth::SignatureGenerator,
      generate_hmac_signature: "hmac_signature")
  end

  let(:request_context) do
    {
      method: "GET",
      url: "https://api.ibkr.com/test",
      query: {page: 1},
      body: {data: "test"},
      live_session_token: "token"
    }
  end

  let(:strategy) { described_class.new(mock_signature_generator, request_context: request_context) }

  describe "#initialize" do
    it "sets request context" do
      expect(strategy.request_context).to eq(request_context)
    end

    it "defaults to empty hash for request context" do
      default_strategy = described_class.new(mock_signature_generator)
      expect(default_strategy.request_context).to eq({})
    end

    it "inherits from Signature" do
      expect(described_class).to be < Ibkr::Oauth::Signature
    end

    it "calls super to set signature_generator" do
      expect(strategy.signature_generator).to eq(mock_signature_generator)
    end

    it "properly initializes with nil signature generator" do
      expect { described_class.new(nil) }.not_to raise_error
      null_strategy = described_class.new(nil)
      expect(null_strategy.signature_generator).to be_nil
    end
  end

  describe "#generate_signature" do
    it "delegates to signature generator's HMAC method with context" do
      params = {"oauth_consumer_key" => "key"}
      result = strategy.generate_signature(params)

      expect(result).to eq("hmac_signature")
      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        method: "GET",
        url: "https://api.ibkr.com/test",
        params: params,
        query: {page: 1},
        body: {data: "test"},
        live_session_token: "token"
      )
    end

    it "handles missing context values gracefully" do
      minimal_strategy = described_class.new(mock_signature_generator, request_context: {method: "POST"})
      params = {"oauth_token" => "token"}

      minimal_strategy.generate_signature(params)

      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        method: "POST",
        url: nil,
        params: params,
        query: {},
        body: {},
        live_session_token: nil
      )
    end

    it "handles context without method key" do
      no_method_strategy = described_class.new(mock_signature_generator, request_context: {url: "https://test.com"})
      params = {"oauth_token" => "token"}

      no_method_strategy.generate_signature(params)

      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        method: nil,
        url: "https://test.com",
        params: params,
        query: {},
        body: {},
        live_session_token: nil
      )
    end

    it "handles completely empty context" do
      empty_strategy = described_class.new(mock_signature_generator, request_context: {})
      params = {"oauth_token" => "token"}

      empty_strategy.generate_signature(params)

      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        method: nil,
        url: nil,
        params: params,
        query: {},
        body: {},
        live_session_token: nil
      )
    end

    it "handles nil request context" do
      # When request_context is nil, accessing with [] returns nil
      nil_strategy = described_class.new(mock_signature_generator, request_context: nil)
      params = {"oauth_token" => "token"}

      # This will raise an error because nil[:method] fails
      expect { nil_strategy.generate_signature(params) }
        .to raise_error(NoMethodError)
    end
  end

  describe "#signature_method" do
    it "returns HMAC-SHA256" do
      expect(strategy.signature_method).to eq("HMAC-SHA256")
    end
  end
end

RSpec.describe Ibkr::Oauth::Signatures do
  let(:mock_signature_generator) { instance_double(Ibkr::Oauth::SignatureGenerator) }

  describe ".create_authentication_strategy" do
    it "creates RSA signature strategy" do
      strategy = described_class.create_authentication_strategy(mock_signature_generator)

      expect(strategy).to be_a(Ibkr::Oauth::RsaSignature)
      expect(strategy.signature_generator).to eq(mock_signature_generator)
    end
  end

  describe ".create_api_strategy" do
    it "creates HMAC signature strategy" do
      strategy = described_class.create_api_strategy(mock_signature_generator)

      expect(strategy).to be_a(Ibkr::Oauth::HmacSignature)
      expect(strategy.signature_generator).to eq(mock_signature_generator)
    end

    it "creates HMAC strategy with request context" do
      context = {method: "GET", url: "https://test.com"}
      strategy = described_class.create_api_strategy(mock_signature_generator, request_context: context)

      expect(strategy).to be_a(Ibkr::Oauth::HmacSignature)
      expect(strategy.request_context).to eq(context)
    end

    it "handles nil request context" do
      strategy = described_class.create_api_strategy(mock_signature_generator, request_context: nil)

      expect(strategy).to be_a(Ibkr::Oauth::HmacSignature)
      # When nil is explicitly passed, it remains nil (not defaulted to {})
      expect(strategy.request_context).to be_nil
    end

    it "passes empty hash when not specified" do
      strategy = described_class.create_api_strategy(mock_signature_generator)

      expect(strategy).to be_a(Ibkr::Oauth::HmacSignature)
      expect(strategy.request_context).to eq({})
    end
  end
end
