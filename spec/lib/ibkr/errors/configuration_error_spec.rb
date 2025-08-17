# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::ConfigurationError do
  describe "base ConfigurationError" do
    context "with default message" do
      subject(:error) { described_class.new }

      it "uses default configuration error message" do
        expect(error.message).to eq("Configuration error")
      end
    end

    context "with custom message" do
      subject(:error) { described_class.new("Custom configuration issue") }

      it "uses the provided message" do
        expect(error.message).to eq("Custom configuration issue")
      end
    end

    context "with additional options" do
      let(:context) { {config_file: "/path/to/config.yml"} }
      subject(:error) { described_class.new("Config issue", context: context) }

      it "passes options to BaseError" do
        expect(error.context).to include(config_file: "/path/to/config.yml")
      end
    end

    describe "inheritance from BaseError" do
      subject(:error) { described_class.new("Test error") }

      it "inherits from BaseError" do
        expect(error).to be_a(Ibkr::BaseError)
      end

      it "generates configuration-specific suggestions" do
        expect(error.suggestions).to include("Check your configuration file for missing or invalid values")
        expect(error.suggestions).to include("Verify file paths exist and are readable")
        expect(error.suggestions).to include("Ensure environment variables are set correctly")
      end

      it "includes helpful debug information" do
        expect(error.debug_info).to include(:error_class, :timestamp)
      end
    end
  end

  describe Ibkr::ConfigurationError::MissingCredentials do
    context "with default message" do
      subject(:error) { described_class.new }

      it "uses default missing credentials message" do
        expect(error.message).to eq("Required credentials are missing")
      end
    end

    context "with custom message" do
      subject(:error) { described_class.new("OAuth credentials not found") }

      it "uses the provided message" do
        expect(error.message).to eq("OAuth credentials not found")
      end
    end

    it "inherits from ConfigurationError" do
      error = described_class.new
      expect(error).to be_a(Ibkr::ConfigurationError)
    end
  end

  describe Ibkr::ConfigurationError::InvalidEnvironment do
    context "with environment parameter" do
      subject(:error) { described_class.new("staging") }

      it "builds descriptive error message with environment name" do
        expect(error.message).to eq("Invalid environment: staging. Must be 'sandbox' or 'production'")
      end
    end

    context "with nil environment" do
      subject(:error) { described_class.new(nil) }

      it "handles nil environment gracefully" do
        expect(error.message).to eq("Invalid environment: . Must be 'sandbox' or 'production'")
      end
    end

    context "with empty string environment" do
      subject(:error) { described_class.new("") }

      it "handles empty environment gracefully" do
        expect(error.message).to eq("Invalid environment: . Must be 'sandbox' or 'production'")
      end
    end

    it "inherits from ConfigurationError" do
      error = described_class.new("test")
      expect(error).to be_a(Ibkr::ConfigurationError)
    end
  end

  describe Ibkr::ConfigurationError::CertificateError do
    context "with default message" do
      subject(:error) { described_class.new }

      it "uses default certificate error message" do
        expect(error.message).to eq("Certificate configuration error")
      end
    end

    context "with custom message" do
      subject(:error) { described_class.new("SSL certificate problem") }

      it "uses the provided message" do
        expect(error.message).to eq("SSL certificate problem")
      end
    end

    it "inherits from ConfigurationError" do
      error = described_class.new
      expect(error).to be_a(Ibkr::ConfigurationError)
    end
  end

  describe Ibkr::ConfigurationError::MissingCertificate do
    context "with certificate type only" do
      subject(:error) { described_class.new("private_key") }

      it "builds message with certificate type" do
        expect(error.message).to eq("Missing private_key certificate")
      end
    end

    context "with certificate type and path" do
      subject(:error) { described_class.new("signature_key", "/path/to/cert.pem") }

      it "builds message with certificate type and path" do
        expect(error.message).to eq("Missing signature_key certificate at path: /path/to/cert.pem")
      end
    end

    context "with nil path" do
      subject(:error) { described_class.new("dh_param", nil) }

      it "omits path information when nil" do
        expect(error.message).to eq("Missing dh_param certificate")
      end
    end

    context "with empty string path" do
      subject(:error) { described_class.new("private_key", "") }

      it "includes empty path information" do
        expect(error.message).to eq("Missing private_key certificate at path: ")
      end
    end

    it "inherits from CertificateError" do
      error = described_class.new("test")
      expect(error).to be_a(Ibkr::ConfigurationError::CertificateError)
    end

    it "inherits from ConfigurationError" do
      error = described_class.new("test")
      expect(error).to be_a(Ibkr::ConfigurationError)
    end
  end

  describe Ibkr::ConfigurationError::InvalidCertificate do
    context "with certificate type and error message" do
      subject(:error) { described_class.new("private_key", "not a valid RSA key") }

      it "builds descriptive error message" do
        expect(error.message).to eq("Invalid private_key certificate: not a valid RSA key")
      end
    end

    context "with complex error message" do
      subject(:error) do
        described_class.new("signature_key", "OpenSSL::PKey::RSAError: padding check failed")
      end

      it "includes the full error details" do
        expect(error.message).to eq("Invalid signature_key certificate: OpenSSL::PKey::RSAError: padding check failed")
      end
    end

    context "with empty error message" do
      subject(:error) { described_class.new("dh_param", "") }

      it "handles empty error message" do
        expect(error.message).to eq("Invalid dh_param certificate: ")
      end
    end

    it "inherits from CertificateError" do
      error = described_class.new("test", "error")
      expect(error).to be_a(Ibkr::ConfigurationError::CertificateError)
    end

    it "inherits from ConfigurationError" do
      error = described_class.new("test", "error")
      expect(error).to be_a(Ibkr::ConfigurationError)
    end
  end

  describe "error hierarchy and polymorphism" do
    let(:config_error) { Ibkr::ConfigurationError.new("Base error") }
    let(:missing_creds) { Ibkr::ConfigurationError::MissingCredentials.new }
    let(:invalid_env) { Ibkr::ConfigurationError::InvalidEnvironment.new("test") }
    let(:cert_error) { Ibkr::ConfigurationError::CertificateError.new }
    let(:missing_cert) { Ibkr::ConfigurationError::MissingCertificate.new("private_key") }
    let(:invalid_cert) { Ibkr::ConfigurationError::InvalidCertificate.new("signature", "bad key") }

    it "allows polymorphic handling of all configuration errors" do
      errors = [config_error, missing_creds, invalid_env, cert_error, missing_cert, invalid_cert]

      errors.each do |error|
        expect(error).to be_a(Ibkr::ConfigurationError)
        expect(error).to be_a(Ibkr::BaseError)
        expect(error).to be_a(StandardError)
      end
    end

    it "allows specific handling of certificate errors" do
      certificate_errors = [cert_error, missing_cert, invalid_cert]

      certificate_errors.each do |error|
        expect(error).to be_a(Ibkr::ConfigurationError::CertificateError)
      end
    end

    it "provides distinct error types for different scenarios" do
      expect(missing_creds.class).to eq(Ibkr::ConfigurationError::MissingCredentials)
      expect(invalid_env.class).to eq(Ibkr::ConfigurationError::InvalidEnvironment)
      expect(missing_cert.class).to eq(Ibkr::ConfigurationError::MissingCertificate)
      expect(invalid_cert.class).to eq(Ibkr::ConfigurationError::InvalidCertificate)
    end
  end

  describe "integration with configuration validation" do
    # These tests ensure the error classes work correctly with the Configuration class

    context "when configuration validation fails" do
      let(:config) { Ibkr::Configuration.new }

      before do
        # Set up partial configuration to trigger specific errors
        config.environment = "invalid"
        config.consumer_key = "test"
        # Missing access_token, access_token_secret, and crypto keys
      end

      it "raises ConfigurationError with validation details" do
        expect { config.validate! }.to raise_error(Ibkr::ConfigurationError) do |error|
          expect(error.message).to include("access_token is required")
          expect(error.message).to include("access_token_secret is required")
          expect(error.message).to include("environment must be 'sandbox' or 'production'")
          expect(error.message).to include("cryptographic keys must be provided")
        end
      end
    end

    context "when crypto key loading fails" do
      let(:config) do
        config = Ibkr::Configuration.new
        config.private_key_content = "invalid key content"
        config
      end

      it "raises ConfigurationError for invalid keys" do
        expect { config.encryption_key }.to raise_error(Ibkr::ConfigurationError) do |error|
          expect(error.message).to include("Invalid private_key:")
        end
      end
    end
  end
end
