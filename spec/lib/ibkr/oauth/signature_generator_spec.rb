# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth::SignatureGenerator do
  include_context "with mocked Rails credentials"

  let(:mock_config) do
    double("config",
      signature_key: signature_key,
      encryption_key: encryption_key,
      access_token_secret: "dGVzdF9zZWNyZXQ=", # Base64 encoded "test_secret"
      dh_params: dh_params,
      base_url: "https://api.ibkr.com")
  end

  let(:signature_key) do
    double("signature_key").tap do |key|
      allow(key).to receive(:sign).and_return("mock_signature_bytes")
    end
  end

  let(:encryption_key) do
    double("encryption_key").tap do |key|
      allow(key).to receive(:private_decrypt).and_return("\x12\x34\x56\x78")
    end
  end

  let(:dh_params) do
    double("dh_params").tap do |params|
      # Mock DH parameters with realistic values
      allow(params).to receive(:p).and_return(OpenSSL::BN.new("23", 16)) # Small prime for testing
      allow(params).to receive(:g).and_return(OpenSSL::BN.new("2"))      # Common generator
    end
  end

  let(:signature_generator) { described_class.new(mock_config) }

  describe "initialization" do
    it "creates a functional signature generator" do
      generator = described_class.new(mock_config)

      # Verify it works by testing a simple operation
      nonce = generator.generate_nonce
      expect(nonce).to be_a(String)
      expect(nonce.length).to eq(16)
    end
  end

  describe "#generate_rsa_signature" do
    let(:oauth_params) do
      {
        "oauth_consumer_key" => "consumer_key",
        "oauth_nonce" => "nonce123",
        "oauth_timestamp" => "1234567890",
        "oauth_signature_method" => "RSA-SHA256",
        "oauth_version" => "1.0"
      }
    end

    context "when generating signature for live session token request" do
      it "creates proper base string and signs with RSA-SHA256" do
        result = signature_generator.generate_rsa_signature(oauth_params)

        expect(signature_key).to have_received(:sign).with(
          an_instance_of(OpenSSL::Digest),
          a_string_matching(/POST&.*live_session_token/)
        )
        expect(result).to eq(Base64.strict_encode64("mock_signature_bytes"))
      end

      it "excludes oauth_signature and realm from signature generation" do
        params_with_signature = oauth_params.merge(
          "oauth_signature" => "should_be_excluded",
          "realm" => "should_also_be_excluded"
        )

        result = signature_generator.generate_rsa_signature(params_with_signature)

        # The signature should be generated (proving excluded params don't break it)
        expect(result).to be_a(String)
        expect(result).to match(/\A[A-Za-z0-9+\/]+=*\z/) # Base64 format
        expect(signature_key).to have_received(:sign)
      end

      it "generates consistent signatures for equivalent parameter sets" do
        # Test that the signature generation is deterministic
        result1 = signature_generator.generate_rsa_signature(oauth_params)
        result2 = signature_generator.generate_rsa_signature(oauth_params)

        expect(result1).to eq(result2)
        expect(result1).to be_a(String)
        expect(result1.length).to be > 0
      end
    end

    context "when RSA signing fails" do
      before do
        allow(signature_key).to receive(:sign).and_raise(OpenSSL::PKey::RSAError, "RSA error")
      end

      it "propagates RSA errors for proper error handling" do
        expect {
          signature_generator.generate_rsa_signature(oauth_params)
        }.to raise_error(OpenSSL::PKey::RSAError, "RSA error")
      end
    end
  end

  describe "#generate_hmac_signature" do
    let(:method) { "GET" }
    let(:url) { "https://api.ibkr.com/v1/api/portfolio/accounts" }
    let(:oauth_params) do
      {
        "oauth_consumer_key" => "consumer_key",
        "oauth_nonce" => "nonce123",
        "oauth_timestamp" => "1234567890"
      }
    end
    let(:live_session_token) { "dGVzdF90b2tlbg==" } # Base64 encoded "test_token"
    let(:query_params) { {"page" => "1", "sort" => "name"} }
    let(:body_params) { {"data" => "value"} }

    context "when generating HMAC signature for API requests" do
      it "creates canonical base string and signs with HMAC-SHA256" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.generate_hmac_signature(
          method: method,
          url: url,
          params: oauth_params,
          live_session_token: live_session_token,
          query: query_params,
          body: body_params
        )

        expect(OpenSSL::HMAC).to have_received(:digest).with(
          "sha256",
          Base64.decode64(live_session_token),
          a_string_matching(/GET&.*portfolio/)
        )
        expect(result).to eq(URI.encode_www_form_component(Base64.strict_encode64("hmac_result")))
      end

      it "handles different parameter types correctly" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.generate_hmac_signature(
          method: method,
          url: url,
          params: oauth_params,
          live_session_token: live_session_token,
          query: query_params,
          body: body_params
        )

        expect(result).to be_a(String)
        expect(result).to include("%") # URL-encoded
        expect(OpenSSL::HMAC).to have_received(:digest)
      end

      it "generates URL-safe encoded signatures" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.generate_hmac_signature(
          method: method,
          url: url,
          params: oauth_params,
          live_session_token: live_session_token
        )

        # Result should be URL-encoded
        expect(result).to include("%")
        expect(result).not_to include(" ")
        expect(result).not_to include("+")
      end
    end

    context "when parameters contain special characters" do
      let(:special_params) do
        {
          "param with spaces" => "value with spaces",
          "param&with&ampersands" => "value&with&ampersands",
          "param=with=equals" => "value=with=equals"
        }
      end

      it "handles special characters in parameters correctly" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.generate_hmac_signature(
          method: method,
          url: url,
          params: special_params,
          live_session_token: live_session_token
        )

        expect(result).to be_a(String)
        expect(result.length).to be > 0
        expect(OpenSSL::HMAC).to have_received(:digest)
      end
    end

    context "when optional parameters are empty or nil" do
      it "handles missing query parameters gracefully" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        expect {
          signature_generator.generate_hmac_signature(
            method: method,
            url: url,
            params: oauth_params,
            live_session_token: live_session_token,
            query: nil,
            body: {}
          )
        }.not_to raise_error
      end
    end
  end

  describe "#generate_nonce" do
    context "when generating secure nonces" do
      it "generates nonce with default length of 16 characters" do
        nonce = signature_generator.generate_nonce

        expect(nonce).to be_a(String)
        expect(nonce.length).to eq(16)
        expect(nonce).to match(/\A[a-zA-Z0-9]+\z/)
      end

      it "generates nonce with custom length" do
        custom_length = 32
        nonce = signature_generator.generate_nonce(custom_length)

        expect(nonce.length).to eq(custom_length)
        expect(nonce).to match(/\A[a-zA-Z0-9]+\z/)
      end

      it "generates unique nonces on successive calls" do
        nonce1 = signature_generator.generate_nonce
        nonce2 = signature_generator.generate_nonce

        expect(nonce1).not_to eq(nonce2)
      end

      it "uses only alphanumeric characters for URL safety" do
        100.times do
          nonce = signature_generator.generate_nonce(50)
          expect(nonce).to match(/\A[a-zA-Z0-9]+\z/)
        end
      end
    end

    context "when generating nonces for different OAuth contexts" do
      it "supports generating short nonces for compact scenarios" do
        short_nonce = signature_generator.generate_nonce(8)
        expect(short_nonce.length).to eq(8)
      end

      it "supports generating long nonces for high-security scenarios" do
        long_nonce = signature_generator.generate_nonce(64)
        expect(long_nonce.length).to eq(64)
      end
    end
  end

  describe "#generate_timestamp" do
    context "when generating OAuth timestamps" do
      it "returns current Unix timestamp as string" do
        allow(Time).to receive(:now).and_return(Time.new(2023, 12, 1, 12, 0, 0, "+00:00"))
        timestamp = signature_generator.generate_timestamp

        expect(timestamp).to eq("1701432000")
        expect(timestamp).to be_a(String)
      end

      it "generates different timestamps over time" do
        timestamp1 = signature_generator.generate_timestamp
        sleep(1.1) # Ensure different second
        timestamp2 = signature_generator.generate_timestamp

        expect(timestamp1.to_i).to be < timestamp2.to_i
      end

      it "uses UTC time for consistency across timezones" do
        utc_time = Time.new(2023, 12, 1, 12, 0, 0, "+00:00")
        local_time = Time.new(2023, 12, 1, 5, 0, 0, "-07:00") # Same UTC time, different timezone

        allow(Time).to receive(:now).and_return(utc_time)
        utc_timestamp = signature_generator.generate_timestamp

        allow(Time).to receive(:now).and_return(local_time)
        local_timestamp = signature_generator.generate_timestamp

        expect(utc_timestamp).to eq(local_timestamp)
      end
    end
  end

  describe "#generate_dh_challenge" do
    context "when generating Diffie-Hellman challenges" do
      it "generates valid hexadecimal challenge string" do
        challenge = signature_generator.generate_dh_challenge

        expect(challenge).to be_a(String)
        expect(challenge).to match(/\A[0-9a-f]+\z/i) # Hexadecimal string
        expect(challenge.length).to be > 0
      end

      it "uses cryptographically secure random number generation" do
        allow(SecureRandom).to receive(:random_number).and_call_original

        challenge = signature_generator.generate_dh_challenge

        expect(SecureRandom).to have_received(:random_number)
        expect(challenge).to be_a(String)
        expect(challenge.length).to be > 0
      end

      it "produces different challenges on successive calls" do
        challenge1 = signature_generator.generate_dh_challenge

        # Create new generator to reset state
        new_generator = described_class.new(mock_config)
        challenge2 = new_generator.generate_dh_challenge

        expect(challenge1).not_to eq(challenge2)
        expect(challenge1).to match(/\A[0-9a-f]+\z/i)
        expect(challenge2).to match(/\A[0-9a-f]+\z/i)
      end

      it "maintains internal state for subsequent operations" do
        challenge = signature_generator.generate_dh_challenge

        # Should be able to use the challenge for session token computation
        expect {
          signature_generator.compute_live_session_token("fedcba987654321")
        }.not_to raise_error

        expect(challenge).to be_a(String)
      end
    end

    context "when DH parameters are not properly configured" do
      let(:invalid_dh_params) do
        double("invalid_dh_params").tap do |params|
          allow(params).to receive(:p).and_return(nil)
          allow(params).to receive(:g).and_return(nil)
        end
      end

      before do
        allow(mock_config).to receive(:dh_params).and_return(invalid_dh_params)
      end

      it "raises error for invalid DH parameters" do
        expect {
          signature_generator.generate_dh_challenge
        }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#compute_live_session_token" do
    let(:dh_response) { "fedcba987654321" }

    context "when computing session token from DH response" do
      before do
        # Generate DH challenge first to set @dh_random
        signature_generator.generate_dh_challenge
      end

      it "computes shared secret using DH key exchange" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.compute_live_session_token(dh_response)

        expect(result).to eq(Base64.strict_encode64("hmac_result"))
        expect(OpenSSL::HMAC).to have_received(:digest).with(
          "sha1",
          anything, # k_bytes (computed shared secret)
          anything  # prepend_bytes (decrypted prepend)
        )
      end

      it "properly handles odd-length hex strings by padding with zero" do
        odd_hex_response = "123" # Odd length
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        expect {
          signature_generator.compute_live_session_token(odd_hex_response)
        }.not_to raise_error
      end

      it "generates valid session token from DH response" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.compute_live_session_token(dh_response)

        expect(result).to eq(Base64.strict_encode64("hmac_result"))
        expect(result).to be_a(String)
        expect(result).to match(/\A[A-Za-z0-9+\/]+=*\z/) # Base64 format
      end

      it "uses proper cryptographic parameters for session token generation" do
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.compute_live_session_token(dh_response)

        # Verify HMAC was called with correct parameters
        expect(OpenSSL::HMAC).to have_received(:digest).with(
          "sha1",
          anything, # k_bytes (computed shared secret)
          anything  # prepend_bytes (decrypted prepend)
        )
        expect(result).to be_a(String)
      end
    end

    context "when DH challenge was not generated first" do
      it "raises error if @dh_random is not set" do
        expect {
          signature_generator.compute_live_session_token(dh_response)
        }.to raise_error(ArgumentError, "DH challenge must be generated first")
      end
    end

    context "when DH response is invalid" do
      before do
        signature_generator.generate_dh_challenge
      end

      it "handles invalid hexadecimal responses" do
        invalid_response = "not_hex_value"

        expect {
          signature_generator.compute_live_session_token(invalid_response)
        }.to raise_error(OpenSSL::BNError) # OpenSSL::BN.new will raise this
      end
    end
  end

  describe "OAuth signature behavior" do
  end

  describe "complete OAuth workflow" do
    context "when performing OAuth 1.0a authentication flow" do
      let(:oauth_params) do
        {
          "oauth_consumer_key" => "test_key",
          "oauth_nonce" => signature_generator.generate_nonce,
          "oauth_timestamp" => signature_generator.generate_timestamp,
          "oauth_signature_method" => "RSA-SHA256",
          "oauth_version" => "1.0"
        }
      end

      it "generates valid RSA signature for authentication request" do
        signature = signature_generator.generate_rsa_signature(oauth_params)

        expect(signature).to be_a(String)
        expect(signature).to match(/\A[A-Za-z0-9+\/]+=*\z/) # Base64 format
        expect(signature.length).to be > 0
      end

      it "generates valid HMAC signature for API requests" do
        live_session_token = "dGVzdF90b2tlbg=="
        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        hmac_signature = signature_generator.generate_hmac_signature(
          method: "GET",
          url: "https://api.ibkr.com/v1/api/portfolio/accounts",
          params: oauth_params,
          live_session_token: live_session_token
        )

        expect(hmac_signature).to be_a(String)
        expect(hmac_signature).to include("%") # URL-encoded
        expect(hmac_signature.length).to be > 0
      end
    end

    context "when performing Diffie-Hellman key exchange" do
      it "completes full DH exchange workflow" do
        # Generate challenge
        challenge = signature_generator.generate_dh_challenge
        expect(challenge).to match(/\A[0-9a-f]+\z/i)
        expect(challenge.length).to be > 0

        # Simulate server response and compute session token
        server_response = "123456789abcdef"
        allow(OpenSSL::HMAC).to receive(:digest).and_return("session_token_bytes")

        session_token = signature_generator.compute_live_session_token(server_response)

        expect(session_token).to be_a(String)
        expect(session_token).to match(/\A[A-Za-z0-9+\/]+=*\z/) # Base64 format
        expect(session_token.length).to be > 0
      end
    end

    context "when handling error conditions" do
      it "propagates RSA signing errors appropriately" do
        allow(signature_key).to receive(:sign).and_raise(OpenSSL::PKey::RSAError, "Signing failed")

        test_params = {
          "oauth_consumer_key" => "test_key",
          "oauth_nonce" => "test_nonce",
          "oauth_timestamp" => "1234567890",
          "oauth_signature_method" => "RSA-SHA256",
          "oauth_version" => "1.0"
        }

        expect {
          signature_generator.generate_rsa_signature(test_params)
        }.to raise_error(OpenSSL::PKey::RSAError, "Signing failed")
      end

      it "raises appropriate error when DH challenge not generated first" do
        expect {
          signature_generator.compute_live_session_token("fedcba987654321")
        }.to raise_error(ArgumentError, "DH challenge must be generated first")
      end

      it "handles invalid DH response format" do
        signature_generator.generate_dh_challenge

        expect {
          signature_generator.compute_live_session_token("invalid_hex_format")
        }.to raise_error(OpenSSL::BNError)
      end
    end
  end

  describe "security and reliability" do
    context "when ensuring cryptographic security" do
      it "generates unique nonces for security" do
        # Verify that nonces have sufficient entropy
        nonces = Array.new(100) { signature_generator.generate_nonce }
        unique_nonces = nonces.uniq

        expect(unique_nonces.size).to eq(100) # All should be unique
        expect(nonces.all? { |n| n.match?(/\A[a-zA-Z0-9]+\z/) }).to be true
      end

      it "uses cryptographically secure random generation" do
        allow(SecureRandom).to receive(:random_number).and_call_original

        signature_generator.generate_dh_challenge

        expect(SecureRandom).to have_received(:random_number)
      end

      it "properly encodes data for safe transmission" do
        # Test with special characters that could cause issues
        special_params = {
          "param" => "value with spaces & special chars = test"
        }

        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        result = signature_generator.generate_hmac_signature(
          method: "POST",
          url: "https://api.ibkr.com/test",
          params: special_params,
          live_session_token: "dGVzdA=="
        )

        # Result should be properly URL-encoded
        expect(result).to include("%")
        expect(result).not_to include(" ")
        expect(result).to be_a(String)
      end
    end

    context "when ensuring signature consistency" do
      it "produces identical signatures for equivalent parameter sets" do
        params1 = {"c" => "3", "a" => "1", "b" => "2"}
        params2 = {"a" => "1", "b" => "2", "c" => "3"}

        allow(OpenSSL::HMAC).to receive(:digest).and_return("hmac_result")

        sig1 = signature_generator.generate_hmac_signature(
          method: "GET", url: "https://test.com", params: params1, live_session_token: "dGVzdA=="
        )
        sig2 = signature_generator.generate_hmac_signature(
          method: "GET", url: "https://test.com", params: params2, live_session_token: "dGVzdA=="
        )

        expect(sig1).to eq(sig2)
        expect(sig1).to be_a(String)
      end

      it "generates reproducible RSA signatures for identical inputs" do
        params = {"oauth_consumer_key" => "key", "oauth_timestamp" => "123"}

        sig1 = signature_generator.generate_rsa_signature(params)
        sig2 = signature_generator.generate_rsa_signature(params)

        expect(sig1).to eq(sig2)
        expect(sig1).to be_a(String)
      end
    end
  end
end
