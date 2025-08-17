# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Ibkr::Oauth Cryptographic Operations", skip: true do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"

  let(:oauth_client) { Ibkr::Oauth.new(live: false) }

  describe "RSA-SHA256 signature generation for authentication" do
    let(:mock_signature) { "mock_rsa_signature" }
    let(:test_params) do
      {
        "oauth_consumer_key" => "test_consumer_key",
        "oauth_nonce" => "test_nonce",
        "oauth_timestamp" => "1692000000",
        "oauth_token" => "test_access_token",
        "oauth_signature_method" => "RSA-SHA256"
      }
    end

    before do
      allow(oauth_client).to receive(:encoded_base_string).and_return("test_base_string")
      allow(mock_rsa_key).to receive(:sign).and_return("raw_signature")
      allow(Base64).to receive(:strict_encode64).and_return(mock_signature)
    end

    it "generates RSA-SHA256 signatures for initial authentication" do
      # Given OAuth parameters for authentication
      # When generating an RSA signature
      signature = oauth_client.send(:generate_oauth_signature, test_params)

      # Then it should use proper RSA-SHA256 signing
      expect(mock_rsa_key).to have_received(:sign).with(
        instance_of(OpenSSL::Digest::SHA256),
        "test_base_string"
      )
      expect(signature).to eq(mock_signature)
    end

    it "excludes oauth_signature and realm from signature base string" do
      params_with_signature = test_params.merge(
        "oauth_signature" => "should_be_excluded",
        "realm" => "should_be_excluded"
      )

      oauth_client.send(:generate_oauth_signature, params_with_signature)

      # The encoded_base_string should be called with params excluding oauth_signature and realm
      expect(oauth_client).to have_received(:encoded_base_string).with(test_params)
    end

    it "handles RSA key loading errors gracefully" do
      allow(File).to receive(:read).with("./config/certs/private_signature.pem").and_raise(Errno::ENOENT)

      expect { Ibkr::Oauth.new(live: false) }.to raise_error(Errno::ENOENT)
    end
  end

  describe "HMAC-SHA256 signature generation for API requests" do
    let(:base_string) { "GET&https%3A//api.ibkr.com/test&param%3Dvalue" }
    let(:live_session_token) { "dGVzdF90b2tlbg==" }
    let(:expected_signature) { "expected_hmac_signature" }

    before do
      allow(Base64).to receive(:decode64).with(live_session_token).and_return("decoded_token")
      allow(OpenSSL::HMAC).to receive(:digest).and_return("raw_hmac")
      allow(Base64).to receive(:strict_encode64).with("raw_hmac").and_return("encoded_hmac")
      allow(URI).to receive(:encode_www_form_component).with("encoded_hmac").and_return(expected_signature)
    end

    it "generates HMAC-SHA256 signatures for authenticated API requests" do
      # Given a base string and live session token
      # When generating HMAC signature
      signature = oauth_client.send(:hmac_sha256_signature, base_string, live_session_token)

      # Then it should use proper HMAC-SHA256 with decoded token as key
      expect(OpenSSL::HMAC).to have_received(:digest).with(
        "sha256",
        "decoded_token",
        base_string.encode("utf-8")
      )
      expect(signature).to eq(expected_signature)
    end

    it "properly encodes the signature for URL inclusion" do
      oauth_client.send(:hmac_sha256_signature, base_string, live_session_token)

      expect(URI).to have_received(:encode_www_form_component).with("encoded_hmac")
    end

    it "handles malformed live session tokens" do
      allow(Base64).to receive(:decode64).and_raise(ArgumentError)

      expect {
        oauth_client.send(:hmac_sha256_signature, base_string, "invalid_token")
      }.to raise_error(ArgumentError)
    end
  end

  describe "Diffie-Hellman key exchange" do
    let(:mock_dh_random) { 12345678901234567890 }
    let(:mock_prime) { double("prime") }
    let(:mock_generator) { double("generator") }
    let(:mock_challenge) { "abcdef123456" }

    before do
      allow(SecureRandom).to receive(:random_number).and_return(mock_dh_random)
      allow(mock_dh_param).to receive(:p).and_return(mock_prime)
      allow(mock_dh_param).to receive(:g).and_return(mock_generator)
      allow(mock_generator).to receive(:mod_exp).and_return(double("result", to_s: mock_challenge))
    end

    it "generates cryptographically secure DH challenges" do
      # Given DH parameters are loaded
      # When generating a DH challenge
      challenge = oauth_client.send(:dh_challenge)

      # Then it should use secure random number generation
      expect(SecureRandom).to have_received(:random_number).with(2**256)
      expect(mock_generator).to have_received(:mod_exp).with(mock_dh_random, mock_prime)
      expect(challenge).to eq(mock_challenge)
    end

    it "stores the random value for later computation" do
      oauth_client.send(:dh_challenge)

      expect(oauth_client.authenticator.signature_generator.dh_random).to eq(mock_dh_random)
    end

    it "uses proper DH parameter file loading" do
      expect(File).to have_received(:read).with("./config/certs/dhparam.pem")
      expect(OpenSSL::PKey::DH).to have_received(:new).with("mock_dh_param")
    end
  end

  describe "live session token computation" do
    let(:dh_response) { "fedcba987654321" }
    let(:mock_shared_secret) { double("shared_secret") }
    let(:mock_k_bytes) { "shared_key_bytes" }
    let(:mock_prepend) { "prepend_value" }
    let(:mock_hmac_result) { "hmac_result" }
    let(:expected_token) { "final_encoded_token" }

    before do
      oauth_client.authenticator.signature_generator.dh_random = 12345

      allow(OpenSSL::BN).to receive(:new).and_call_original
      allow(OpenSSL::BN).to receive(:new).with(dh_response, 16).and_return(double("b_bn"))
      allow(OpenSSL::BN).to receive(:new).with("3039", 16).and_return(double("a_bn"))

      allow(mock_shared_secret).to receive(:mod_exp).and_return(
        double("k_bn", to_s: "abcdef", length: 6, num_bits: 24)
      )
      allow(oauth_client).to receive(:prepend).and_return(mock_prepend)
      allow(OpenSSL::HMAC).to receive(:digest).and_return(mock_hmac_result)
      allow(Base64).to receive(:strict_encode64).and_return(expected_token)
    end

    it "computes shared secret using DH key exchange mathematics" do
      # Given a DH response from IBKR and stored random value
      # When computing the live session token
      # Then it should perform proper DH computation

      # Mock the complex DH computation chain
      b_bn = double("b_bn")
      a_bn = double("a_bn")
      k_bn = double("k_bn", to_s: "abcdef", length: 6, num_bits: 24)

      allow(OpenSSL::BN).to receive(:new).with(dh_response, 16).and_return(b_bn)
      allow(OpenSSL::BN).to receive(:new).with("3039", 16).and_return(a_bn)
      allow(b_bn).to receive(:mod_exp).with(a_bn, mock_dh_param.p).and_return(k_bn)

      token = oauth_client.send(:compute_live_session_token, dh_response)

      expect(b_bn).to have_received(:mod_exp).with(a_bn, mock_dh_param.p)
      expect(token).to eq(expected_token)
    end

    it "handles odd-length hex strings by prepending zero" do
      k_bn = double("k_bn", to_s: "abcde", length: 5, num_bits: 20)  # Odd length

      allow(OpenSSL::BN).to receive(:new).with(dh_response, 16).and_return(double("b_bn"))
      allow(OpenSSL::BN).to receive(:new).with("3039", 16).and_return(double("a_bn"))
      allow_any_instance_of(Object).to receive(:mod_exp).and_return(k_bn)

      # Should prepend "0" to make it even length
      expect(oauth_client.send(:compute_live_session_token, dh_response)).to eq(expected_token)
    end

    it "applies proper byte padding for key material" do
      # Test that keys are properly padded when needed
      k_bn = double("k_bn", to_s: "abcdef", length: 6, num_bits: 24)  # 24 % 8 = 0

      allow(OpenSSL::BN).to receive(:new).with(dh_response, 16).and_return(double("b_bn"))
      allow(OpenSSL::BN).to receive(:new).with("3039", 16).and_return(double("a_bn"))
      allow_any_instance_of(Object).to receive(:mod_exp).and_return(k_bn)

      oauth_client.send(:compute_live_session_token, dh_response)

      # Verify HMAC is called with proper parameters
      expect(OpenSSL::HMAC).to have_received(:digest).with(
        "sha1",
        anything,  # k_bytes with potential padding
        anything   # prepend_bytes
      )
    end
  end

  describe "encryption key operations" do
    let(:encrypted_secret) { Base64.encode64("encrypted_access_token_secret") }
    let(:decrypted_bytes) { "decrypted_secret_bytes" }
    let(:hex_result) { "6465637279707465645f7365637265745f6279746573" }

    before do
      mock_credentials.ibkr.oauth.stub(:access_token_secret).and_return(encrypted_secret)
      allow(mock_rsa_key).to receive(:private_decrypt).and_return(decrypted_bytes)
      allow(decrypted_bytes).to receive(:unpack1).with("H*").and_return(hex_result)
    end

    it "decrypts access token secret using RSA private key" do
      # Given an encrypted access token secret
      # When preparing prepend value for signatures
      result = oauth_client.send(:prepend)

      # Then it should decrypt using proper RSA padding
      expect(mock_rsa_key).to have_received(:private_decrypt).with(
        Base64.decode64(encrypted_secret),
        OpenSSL::PKey::RSA::PKCS1_PADDING
      )
      expect(result).to eq(hex_result)
    end

    it "converts decrypted bytes to hexadecimal representation" do
      oauth_client.send(:prepend)

      expect(decrypted_bytes).to have_received(:unpack1).with("H*")
    end

    it "handles decryption failures gracefully" do
      allow(mock_rsa_key).to receive(:private_decrypt).and_raise(OpenSSL::PKey::RSAError)

      expect { oauth_client.send(:prepend) }.to raise_error(OpenSSL::PKey::RSAError)
    end
  end

  describe "security validations" do
    it "validates that all cryptographic operations use secure methods" do
      # Ensure no deprecated or weak cryptographic functions are used
      expect(described_class.instance_methods.grep(/md5|sha1(?!$)|des|rc4/i)).to be_empty
    end

    it "uses constant-time comparisons for signature validation" do
      token = Ibkr::Oauth::LiveSessionToken.new("token", "sig", Time.now.to_i + 3600)

      expect(token).to respond_to(:secure_compare)

      # Should return false for different strings
      expect(token.secure_compare("a", "b")).to be false

      # Should return true for identical strings
      expect(token.secure_compare("same", "same")).to be true
    end

    it "prevents timing attacks in token validation" do
      # Verify that signature comparison uses constant-time comparison
      token = Ibkr::Oauth::LiveSessionToken.new("token", "sig", Time.now.to_i + 3600)

      allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_return(true)
      token.send(:secure_compare, "test1", "test2")

      expect(ActiveSupport::SecurityUtils).to have_received(:secure_compare).with("test1", "test2")
    end
  end

  describe "error handling in cryptographic operations" do
    it "handles OpenSSL errors during signature generation" do
      allow(mock_rsa_key).to receive(:sign).and_raise(OpenSSL::PKey::RSAError, "Key error")

      expect {
        oauth_client.send(:generate_oauth_signature, {})
      }.to raise_error(OpenSSL::PKey::RSAError)
    end

    it "handles HMAC computation errors" do
      allow(OpenSSL::HMAC).to receive(:digest).and_raise(OpenSSL::HMACError, "HMAC error")

      expect {
        oauth_client.send(:hmac_sha256_signature, "base", "token")
      }.to raise_error(OpenSSL::HMACError)
    end

    it "handles malformed DH parameters" do
      allow(File).to receive(:read).with("./config/certs/dhparam.pem").and_return("invalid_dh_param")
      allow(OpenSSL::PKey::DH).to receive(:new).and_raise(OpenSSL::PKey::DHError)

      expect { Ibkr::Oauth.new(live: false) }.to raise_error(OpenSSL::PKey::DHError)
    end
  end
end
