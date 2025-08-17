# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Ibkr::Configuration do
  let(:config) { described_class.new }

  describe "initialization" do
    context "when created with default values" do
      it "sets environment to sandbox" do
        expect(config.environment).to eq("sandbox")
      end

      it "sets timeout to 30 seconds" do
        expect(config.timeout).to eq(30)
      end

      it "sets retries to 3" do
        expect(config.retries).to eq(3)
      end

      it "sets logger level to info" do
        expect(config.logger_level).to eq("info")
      end

      it "sets user agent with gem version" do
        expect(config.user_agent).to eq("IBKR Ruby Client #{Ibkr::VERSION}")
      end

      it "initializes repository type to api" do
        expect(config.repository_type).to eq(:api)
      end

      it "initializes cache TTL settings" do
        expect(config.cache_ttl).to eq({
          summary: 30,
          metadata: 300,
          positions: 10,
          transactions: 60,
          accounts: 60
        })
      end
    end

    context "when created with custom values" do
      let(:config) do
        described_class.new(
          environment: "production",
          timeout: 60,
          retries: 5,
          logger_level: "debug",
          user_agent: "Custom Agent"
        )
      end

      it "respects custom environment" do
        expect(config.environment).to eq("production")
      end

      it "respects custom timeout" do
        expect(config.timeout).to eq(60)
      end

      it "respects custom retries" do
        expect(config.retries).to eq(5)
      end

      it "respects custom logger level" do
        expect(config.logger_level).to eq("debug")
      end

      it "respects custom user agent" do
        expect(config.user_agent).to eq("Custom Agent")
      end
    end
  end

  describe "environment helpers" do
    context "when environment is sandbox" do
      before { config.environment = "sandbox" }

      it "returns true for sandbox?" do
        expect(config.sandbox?).to be true
      end

      it "returns false for production?" do
        expect(config.production?).to be false
      end
    end

    context "when environment is production" do
      before { config.environment = "production" }

      it "returns false for sandbox?" do
        expect(config.sandbox?).to be false
      end

      it "returns true for production?" do
        expect(config.production?).to be true
      end
    end
  end

  describe "base URL configuration" do
    context "when base_url is not explicitly set" do
      context "in sandbox environment" do
        before { config.environment = "sandbox" }

        it "returns the IBKR API URL" do
          expect(config.base_url).to eq("https://api.ibkr.com")
        end
      end

      context "in production environment" do
        before { config.environment = "production" }

        it "returns the IBKR API URL" do
          expect(config.base_url).to eq("https://api.ibkr.com")
        end
      end

      context "with unknown environment" do
        before { config.environment = "unknown" }

        it "raises a configuration error" do
          expect { config.base_url }.to raise_error(
            Ibkr::ConfigurationError,
            "Unknown environment: unknown"
          )
        end
      end
    end

    context "when base_url is explicitly set" do
      before { config.base_url = "https://custom.api.com" }

      it "returns the custom URL" do
        expect(config.base_url).to eq("https://custom.api.com")
      end
    end
  end

  describe "validation" do
    context "with complete valid configuration" do
      before do
        config.consumer_key = "test_key"
        config.access_token = "test_token"
        config.access_token_secret = "test_secret"
        config.environment = "sandbox"

        # Provide cryptographic content directly
        config.private_key_content = generate_rsa_key
        config.signature_key_content = generate_rsa_key
        config.dh_param_content = generate_dh_params
      end

      it "passes validation" do
        expect(config.validate!).to be true
      end
    end

    context "with missing OAuth credentials" do
      before do
        config.private_key_content = generate_rsa_key
        config.signature_key_content = generate_rsa_key
        config.dh_param_content = generate_dh_params
      end

      it "fails validation when consumer_key is missing" do
        config.access_token = "token"
        config.access_token_secret = "secret"

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /consumer_key is required/
        )
      end

      it "fails validation when consumer_key is empty" do
        config.consumer_key = ""
        config.access_token = "token"
        config.access_token_secret = "secret"

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /consumer_key is required/
        )
      end

      it "fails validation when access_token is missing" do
        config.consumer_key = "key"
        config.access_token_secret = "secret"

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /access_token is required/
        )
      end

      it "fails validation when access_token is empty" do
        config.consumer_key = "key"
        config.access_token = ""
        config.access_token_secret = "secret"

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /access_token is required/
        )
      end

      it "fails validation when access_token_secret is missing" do
        config.consumer_key = "key"
        config.access_token = "token"

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /access_token_secret is required/
        )
      end

      it "fails validation when access_token_secret is empty" do
        config.consumer_key = "key"
        config.access_token = "token"
        config.access_token_secret = ""

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /access_token_secret is required/
        )
      end
    end

    context "with invalid environment" do
      before do
        config.consumer_key = "key"
        config.access_token = "token"
        config.access_token_secret = "secret"
        config.private_key_content = generate_rsa_key
        config.signature_key_content = generate_rsa_key
        config.dh_param_content = generate_dh_params
      end

      it "fails validation for unknown environment" do
        config.environment = "invalid"

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /environment must be 'sandbox' or 'production'/
        )
      end
    end

    context "with missing cryptographic keys" do
      before do
        config.consumer_key = "key"
        config.access_token = "token"
        config.access_token_secret = "secret"
        config.environment = "sandbox"
      end

      it "fails validation when no crypto keys are provided" do
        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /cryptographic keys must be provided/
        )
      end

      it "fails validation when only some crypto keys are provided" do
        config.private_key_content = generate_rsa_key
        # Missing signature key and dh params

        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError,
          /cryptographic keys must be provided/
        )
      end
    end

    context "with multiple validation errors" do
      it "includes all errors in the exception message" do
        expect { config.validate! }.to raise_error(
          Ibkr::ConfigurationError
        ) do |error|
          expect(error.message).to include("consumer_key is required")
          expect(error.message).to include("access_token is required")
          expect(error.message).to include("access_token_secret is required")
          expect(error.message).to include("cryptographic keys must be provided")
        end
      end
    end
  end

  describe "cryptographic key loading" do
    let(:rsa_key_content) { generate_rsa_key }
    let(:dh_params_content) { generate_dh_params }

    context "loading keys from content" do
      before do
        config.private_key_content = rsa_key_content
        config.signature_key_content = rsa_key_content
        config.dh_param_content = dh_params_content
      end

      it "loads encryption key successfully" do
        key = config.encryption_key
        expect(key).to be_a(OpenSSL::PKey::RSA)
      end

      it "loads signature key successfully" do
        key = config.signature_key
        expect(key).to be_a(OpenSSL::PKey::RSA)
      end

      it "loads DH parameters successfully" do
        params = config.dh_params
        expect(params).to be_a(OpenSSL::PKey::DH)
      end

      it "caches loaded keys" do
        key1 = config.encryption_key
        key2 = config.encryption_key
        expect(key1).to be(key2)
      end
    end

    context "loading keys from files" do
      let(:temp_key_file) { create_temp_file(rsa_key_content) }
      let(:temp_dh_file) { create_temp_file(dh_params_content) }

      before do
        config.private_key_path = temp_key_file.path
        config.signature_key_path = temp_key_file.path
        config.dh_param_path = temp_dh_file.path
      end

      after do
        temp_key_file.close
        temp_key_file.unlink
        temp_dh_file.close
        temp_dh_file.unlink
      end

      it "loads encryption key from file" do
        key = config.encryption_key
        expect(key).to be_a(OpenSSL::PKey::RSA)
      end

      it "loads signature key from file" do
        key = config.signature_key
        expect(key).to be_a(OpenSSL::PKey::RSA)
      end

      it "loads DH parameters from file" do
        params = config.dh_params
        expect(params).to be_a(OpenSSL::PKey::DH)
      end
    end

    context "with content taking precedence over file paths" do
      let(:temp_file) { create_temp_file("invalid content") }

      before do
        config.private_key_content = rsa_key_content
        config.private_key_path = temp_file.path
      end

      after do
        temp_file.close
        temp_file.unlink
      end

      it "uses content instead of file path" do
        key = config.encryption_key
        expect(key).to be_a(OpenSSL::PKey::RSA)
      end
    end

    context "with invalid key content" do
      before do
        config.private_key_content = "invalid key content"
      end

      it "raises configuration error for invalid private key" do
        expect { config.encryption_key }.to raise_error(
          Ibkr::ConfigurationError,
          /Invalid private_key:/
        )
      end
    end

    context "with invalid DH parameters" do
      before do
        config.dh_param_content = "invalid dh params"
      end

      it "raises configuration error for invalid DH parameters" do
        expect { config.dh_params }.to raise_error(
          Ibkr::ConfigurationError,
          /Invalid DH parameters:/
        )
      end
    end

    context "with non-existent file paths" do
      before do
        config.private_key_path = "/non/existent/path"
      end

      it "raises configuration error" do
        expect { config.encryption_key }.to raise_error(
          Ibkr::ConfigurationError,
          /private key not found: \/non\/existent\/path/
        )
      end
    end

    context "with no key provided" do
      it "raises configuration error" do
        expect { config.encryption_key }.to raise_error(
          Ibkr::ConfigurationError,
          /private key not found: no path provided/
        )
      end
    end
  end

  describe "key reset functionality" do
    before do
      config.private_key_content = generate_rsa_key
      config.signature_key_content = generate_rsa_key
      config.dh_param_content = generate_dh_params
    end

    it "clears cached keys when reset" do
      # Load keys to cache them
      original_encryption_key = config.encryption_key
      original_signature_key = config.signature_key
      original_dh_params = config.dh_params

      # Reset keys
      config.reset_keys!

      # New keys should be loaded (different object instances)
      new_encryption_key = config.encryption_key
      new_signature_key = config.signature_key
      new_dh_params = config.dh_params

      expect(new_encryption_key).not_to be(original_encryption_key)
      expect(new_signature_key).not_to be(original_signature_key)
      expect(new_dh_params).not_to be(original_dh_params)
    end
  end

  describe "repository configuration" do
    it "allows setting repository type" do
      config.repository_type = :test
      expect(config.repository_type).to eq(:test)
    end

    it "allows modifying cache TTL settings" do
      config.cache_ttl[:summary] = 60
      expect(config.cache_ttl[:summary]).to eq(60)
    end
  end

  private

  def generate_rsa_key
    # Use smaller RSA key for testing (1024-bit instead of 2048)
    # This is faster but less secure - only for testing!
    OpenSSL::PKey::RSA.new(1024).to_pem
  end

  def generate_dh_params
    # Use pre-generated small DH parameters for testing (512-bit)
    # DO NOT use this in production! This is only for test speed.
    <<~DH_PARAMS
      -----BEGIN DH PARAMETERS-----
      MEYCQQDxSfEm6gWgmpczgLLNCzkmNvAuL7+jFNOmHb2TZD8K5QkjJRy0mCUB75DA
      sNt+PgVqK1loY/l9MDPYN3nk5VPvAgEC
      -----END DH PARAMETERS-----
    DH_PARAMS
  end

  def create_temp_file(content)
    file = Tempfile.new
    file.write(content)
    file.rewind
    file
  end
end
