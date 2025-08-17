# frozen_string_literal: true

module Ibkr
  module Oauth
    # Abstract base class for OAuth signature generation
    # Defines interface for different signature methods
    class Signature
      attr_reader :signature_generator

      def initialize(signature_generator)
        @signature_generator = signature_generator
      end

      # Template method defining the signature generation process
      def generate_signature(params)
        raise NotImplementedError, "Subclasses must implement #generate_signature"
      end

      def signature_method
        raise NotImplementedError, "Subclasses must implement #signature_method"
      end
    end

    # RSA-SHA256 signature implementation for authentication requests
    class RsaSignature < Signature
      def generate_signature(params)
        signature_generator.generate_rsa_signature(params)
      end

      def signature_method
        "RSA-SHA256"
      end
    end

    # HMAC-SHA256 signature implementation for API requests
    class HmacSignature < Signature
      attr_reader :request_context

      def initialize(signature_generator, request_context: {})
        super(signature_generator)
        @request_context = request_context
      end

      def generate_signature(params)
        signature_generator.generate_hmac_signature(
          method: request_context[:method],
          url: request_context[:url],
          params: params,
          query: request_context[:query] || {},
          body: request_context[:body] || {},
          live_session_token: request_context[:live_session_token]
        )
      end

      def signature_method
        "HMAC-SHA256"
      end
    end

    # Factory for creating appropriate signature implementations
    class Signatures
      def self.create_authentication_strategy(signature_generator)
        RsaSignature.new(signature_generator)
      end

      def self.create_api_strategy(signature_generator, request_context: {})
        HmacSignature.new(signature_generator, request_context: request_context)
      end
    end
  end
end
