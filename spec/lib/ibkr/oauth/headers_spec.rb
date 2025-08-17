# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth::Headers do
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
      generate_rsa_signature: "rsa_signature",
      generate_hmac_signature: "hmac_signature")
  end

  let(:factory) { described_class.new(config: mock_config, signature_generator: mock_signature_generator) }

  describe "#initialize" do
    it "sets config and signature generator" do
      expect(factory.config).to eq(mock_config)
      expect(factory.signature_generator).to eq(mock_signature_generator)
    end
  end

  describe "#create_authentication_header" do
    it "creates properly formatted authentication header" do
      header = factory.create_authentication_header

      expect(header).to include('oauth_consumer_key="test_consumer_key"')
      expect(header).to include('oauth_token="test_access_token"')
      expect(header).to include('oauth_nonce="test_nonce"')
      expect(header).to include('oauth_timestamp="1234567890"')
      expect(header).to include('oauth_signature_method="RSA-SHA256"')
      expect(header).to include('diffie_hellman_challenge="dh_challenge"')
      expect(header).to include("oauth_signature=")
      expect(header).to include('realm="test_realm"')
    end

    it "generates unique values for each call" do
      allow(mock_signature_generator).to receive(:generate_nonce).and_return("nonce1", "nonce2")
      allow(mock_signature_generator).to receive(:generate_timestamp).and_return("time1", "time2")

      header1 = factory.create_authentication_header
      header2 = factory.create_authentication_header

      expect(header1).not_to eq(header2)
    end

    context "in production" do
      before do
        allow(mock_config).to receive(:production?).and_return(true)
      end

      it "uses production realm" do
        header = factory.create_authentication_header
        expect(header).to include('realm="limited_poa"')
      end
    end
  end

  describe "#create_api_header" do
    let(:request_params) do
      {
        method: "GET",
        url: "https://api.ibkr.com/test",
        query: {page: 1},
        body: {data: "test"},
        live_session_token: "live_token"
      }
    end

    it "creates properly formatted API request header" do
      header = factory.create_api_header(**request_params)

      expect(header).to include('oauth_consumer_key="test_consumer_key"')
      expect(header).to include('oauth_token="test_access_token"')
      expect(header).to include('oauth_signature_method="HMAC-SHA256"')
      expect(header).to include("oauth_signature=")
      expect(header).to include('realm="test_realm"')
    end

    it "passes request context to signature generator" do
      factory.create_api_header(**request_params)

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

    it "handles empty query and body parameters" do
      minimal_params = {
        method: "POST",
        url: "https://api.ibkr.com/simple",
        live_session_token: "token"
      }

      header = factory.create_api_header(**minimal_params)
      expect(header).to include('oauth_signature_method="HMAC-SHA256"')

      expect(mock_signature_generator).to have_received(:generate_hmac_signature).with(
        hash_including(query: {}, body: {})
      )
    end

    it "passes nil query parameter to builder" do
      params_with_nil_query = {
        method: "DELETE",
        url: "https://api.ibkr.com/resource",
        query: nil,
        body: {id: "123"},
        live_session_token: "token"
      }

      # Should not raise error - builder handles nil
      header = factory.create_api_header(**params_with_nil_query)
      expect(header).to include('oauth_signature_method="HMAC-SHA256"')

      # Verify the builder received nil (not empty hash)
      expect(Ibkr::Oauth::ApiParameters).to receive(:new).with(
        hash_including(
          request_params: hash_including(query: nil)
        )
      ).and_call_original

      factory.create_api_header(**params_with_nil_query)
    end

    it "passes nil body parameter to builder" do
      params_with_nil_body = {
        method: "GET",
        url: "https://api.ibkr.com/resource",
        query: {id: "123"},
        body: nil,
        live_session_token: "token"
      }

      # Should not raise error - builder handles nil
      header = factory.create_api_header(**params_with_nil_body)
      expect(header).to include('oauth_signature_method="HMAC-SHA256"')

      # Verify the builder received nil (not empty hash)
      expect(Ibkr::Oauth::ApiParameters).to receive(:new).with(
        hash_including(
          request_params: hash_including(body: nil)
        )
      ).and_call_original

      factory.create_api_header(**params_with_nil_body)
    end

    it "preserves empty hash default for query when not provided" do
      # Verify that ApiParameters receives empty hash when query is omitted
      expect(Ibkr::Oauth::ApiParameters).to receive(:new).with(
        hash_including(
          request_params: hash_including(query: {})
        )
      ).and_call_original

      params_no_query = {
        method: "GET",
        url: "https://api.ibkr.com/test",
        body: {data: "test"},
        live_session_token: "token"
      }

      factory.create_api_header(**params_no_query)
    end

    it "preserves empty hash default for body when not provided" do
      # Verify that ApiParameters receives empty hash when body is omitted
      expect(Ibkr::Oauth::ApiParameters).to receive(:new).with(
        hash_including(
          request_params: hash_including(body: {})
        )
      ).and_call_original

      params_no_body = {
        method: "POST",
        url: "https://api.ibkr.com/test",
        query: {page: 1},
        live_session_token: "token"
      }

      factory.create_api_header(**params_no_body)
    end
  end

  describe "header formatting" do
    it "sorts parameters alphabetically" do
      # Create a factory with predictable values
      allow(mock_signature_generator).to receive(:generate_nonce).and_return("abc")
      allow(mock_signature_generator).to receive(:generate_timestamp).and_return("123")

      header = factory.create_authentication_header

      # The header should be sorted alphabetically
      parts = header.split(", ")
      sorted_parts = parts.sort
      expect(parts).to eq(sorted_parts)
    end

    it "properly quotes all values" do
      header = factory.create_authentication_header

      # Each part should be in format key="value"
      parts = header.split(", ")
      parts.each do |part|
        expect(part).to match(/\A[\w_]+="[^"]*"\z/)
      end
    end

    it "formats header with special characters in values" do
      allow(mock_signature_generator).to receive(:generate_nonce).and_return("special=chars&here")
      allow(mock_signature_generator).to receive(:generate_rsa_signature).and_return("sig+with+plus")

      header = factory.create_authentication_header

      # Values should be quoted but signature should be encoded
      expect(header).to include('oauth_nonce="special=chars&here"')
      expect(header).to include('oauth_signature="sig%2Bwith%2Bplus"')
    end

    it "handles empty parameter hash" do
      # Test private method directly through send
      formatted = factory.send(:format_oauth_header, {})
      expect(formatted).to eq("")
    end

    it "formats single parameter correctly" do
      formatted = factory.send(:format_oauth_header, {"key" => "value"})
      expect(formatted).to eq('key="value"')
    end

    it "formats multiple parameters with proper sorting" do
      params = {
        "zebra" => "last",
        "alpha" => "first",
        "middle" => "center"
      }
      formatted = factory.send(:format_oauth_header, params)
      expect(formatted).to eq('alpha="first", middle="center", zebra="last"')
    end
  end

  describe "edge cases" do
    it "handles nil config values gracefully" do
      nil_config = double("config",
        consumer_key: nil,
        access_token: nil,
        production?: false)

      nil_factory = described_class.new(config: nil_config, signature_generator: mock_signature_generator)

      header = nil_factory.create_authentication_header
      expect(header).to include('oauth_consumer_key=""')
      expect(header).to include('oauth_token=""')
    end

    it "handles empty string values" do
      empty_config = double("config",
        consumer_key: "",
        access_token: "",
        production?: false)

      empty_factory = described_class.new(config: empty_config, signature_generator: mock_signature_generator)

      header = empty_factory.create_authentication_header
      expect(header).to include('oauth_consumer_key=""')
      expect(header).to include('oauth_token=""')
    end

    it "preserves parameter immutability" do
      # Create API header and verify original params aren't modified
      params = {
        method: "GET",
        url: "https://api.ibkr.com/test",
        query: {page: 1},
        body: {data: "test"},
        live_session_token: "token"
      }

      original_query = params[:query].dup
      original_body = params[:body].dup

      factory.create_api_header(**params)

      expect(params[:query]).to eq(original_query)
      expect(params[:body]).to eq(original_body)
    end
  end
end
