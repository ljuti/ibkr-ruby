# frozen_string_literal: true

module Ibkr
  class ConfigurationError < BaseError
    def initialize(message = "Configuration error", **options)
      super(message, **options)
    end

    # Specific configuration error types
    class MissingCredentials < ConfigurationError
      def initialize(message = "Required credentials are missing")
        super(message)
      end
    end

    class InvalidEnvironment < ConfigurationError
      def initialize(environment)
        super("Invalid environment: #{environment}. Must be 'sandbox' or 'production'")
      end
    end

    class CertificateError < ConfigurationError
      def initialize(message = "Certificate configuration error")
        super(message)
      end
    end

    class MissingCertificate < CertificateError
      def initialize(cert_type, path = nil)
        message = "Missing #{cert_type} certificate"
        message += " at path: #{path}" if path
        super(message)
      end
    end

    class InvalidCertificate < CertificateError
      def initialize(cert_type, error_message)
        super("Invalid #{cert_type} certificate: #{error_message}")
      end
    end
  end
end