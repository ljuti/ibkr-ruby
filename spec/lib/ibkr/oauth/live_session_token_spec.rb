# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth::LiveSessionToken do
  include_context "with mocked Rails credentials"

  let(:valid_token) { "dGVzdF90b2tlbg==" }  # Base64 encoded "test_token"
  let(:valid_signature) { "expected_signature" }
  let(:future_expiration) { (Time.now + 3600).to_i }
  let(:past_expiration) { (Time.now - 3600).to_i }

  let(:live_session_token) do
    described_class.new(valid_token, valid_signature, future_expiration)
  end

  describe "initialization" do
    it "stores token, signature, and expiration data" do
      token = described_class.new(valid_token, valid_signature, future_expiration)
      
      expect(token.token).to eq(valid_token)
      expect(token.expires_in).to eq(future_expiration)
      expect(token.instance_variable_get(:@signature)).to eq(valid_signature)
    end
  end

  describe "#expired?" do
    context "with valid expiration time" do
      it "returns false for future expiration times" do
        token = described_class.new(valid_token, valid_signature, future_expiration)
        expect(token.expired?).to be false
      end

      it "returns true for past expiration times" do
        token = described_class.new(valid_token, valid_signature, past_expiration)
        expect(token.expired?).to be true
      end
    end

    context "with nil expiration time" do
      it "returns false when expiration is not set" do
        token = described_class.new(valid_token, valid_signature, nil)
        expect(token.expired?).to be false
      end
    end

    context "with invalid expiration format" do
      it "handles invalid expiration gracefully and returns true" do
        allow(Rails.logger).to receive(:error)
        token = described_class.new(valid_token, valid_signature, "invalid_timestamp")
        
        expect(token.expired?).to be true
        expect(Rails.logger).to have_received(:error).with(/Invalid expiration time/)
      end
    end
  end

  describe "#valid_signature?" do
    let(:expected_hmac_hex) { "expected_signature" }

    before do
      # Mock the HMAC calculation to return our expected signature
      allow(OpenSSL::HMAC).to receive(:hexdigest).and_return(expected_hmac_hex)
      allow(live_session_token).to receive(:secure_compare).and_return(true)
    end

    context "when signature verification succeeds" do
      it "validates signature using HMAC-SHA1 with consumer key" do
        # Given a token with a valid signature
        # When signature validation is performed
        result = live_session_token.valid_signature?
        
        # Then it should use proper cryptographic validation
        expect(OpenSSL::HMAC).to have_received(:hexdigest).with(
          "sha1",
          Base64.decode64(valid_token),
          "test_consumer_key"
        )
        expect(result).to be true
      end

      it "uses secure comparison to prevent timing attacks" do
        live_session_token.valid_signature?
        expect(live_session_token).to have_received(:secure_compare)
      end
    end

    context "when signature verification fails" do
      before do
        allow(live_session_token).to receive(:secure_compare).and_return(false)
      end

      it "returns false for invalid signatures" do
        expect(live_session_token.valid_signature?).to be false
      end
    end

    include_examples "a secure token operation" do
      # Override the mock to not stub secure_compare for this test
      before do
        allow(OpenSSL::HMAC).to receive(:hexdigest).and_return(expected_hmac_hex)
        # Remove the secure_compare mock so the real implementation gets called
        allow(live_session_token).to receive(:secure_compare).and_call_original
      end
      
      subject { live_session_token.valid_signature? }
    end
  end

  describe "#valid?" do
    context "when token is not expired and has valid signature" do
      before do
        allow(live_session_token).to receive(:expired?).and_return(false)
        allow(live_session_token).to receive(:valid_signature?).and_return(true)
      end

      it "returns true for valid, non-expired tokens" do
        expect(live_session_token.valid?).to be true
      end
    end

    context "when token is expired" do
      before do
        allow(live_session_token).to receive(:expired?).and_return(true)
      end

      it "returns false even with valid signature" do
        expect(live_session_token.valid?).to be false
      end
    end

    context "when signature is invalid" do
      before do
        allow(live_session_token).to receive(:expired?).and_return(false)
        allow(live_session_token).to receive(:valid_signature?).and_return(false)
      end

      it "returns false even when not expired" do
        expect(live_session_token.valid?).to be false
      end
    end
  end

  describe "#secure_compare" do
    context "when using ActiveSupport::SecurityUtils" do
      it "delegates to secure comparison utility" do
        expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).with("a", "b").and_return(true)
        result = live_session_token.secure_compare("a", "b")
        expect(result).to be true
      end

      it "handles comparison errors gracefully" do
        allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_raise(ArgumentError)
        result = live_session_token.secure_compare("a", "b")
        expect(result).to be false
      end
    end
  end

  describe "token lifecycle scenarios" do
    it "handles token refresh scenarios" do
      # Given an expired token
      expired_token = described_class.new(valid_token, valid_signature, past_expiration)
      expect(expired_token.valid?).to be false
      
      # When a new token is created with fresh expiration
      refreshed_token = described_class.new(valid_token, valid_signature, future_expiration)
      allow(refreshed_token).to receive(:valid_signature?).and_return(true)
      
      # Then the new token should be valid
      expect(refreshed_token.valid?).to be true
    end

    it "validates tokens received from IBKR API" do
      # Given a token structure as returned by IBKR
      api_token = described_class.new(
        "YXBpX3Rva2VuX2Zyb21faWJrcg==",
        "api_signature_from_ibkr", 
        (Time.now + 1800).to_i
      )
      
      # When validating the token structure
      # Then it should be properly initialized
      expect(api_token.token).to eq("YXBpX3Rva2VuX2Zyb21faWJrcg==")
      expect(api_token.expires_in).to be > Time.now.to_i
      expect(api_token.expired?).to be false
    end
  end
end