# frozen_string_literal: true

module Ibkr
  class AuthenticationError < BaseError
    def initialize(message = "Authentication failed", **options)
      super
    end

    # Specific authentication error types
    class InvalidCredentials < AuthenticationError
      def initialize(message = "Invalid credentials provided", **options)
        super
      end
    end

    class TokenExpired < AuthenticationError
      def initialize(message = "Access token has expired", **options)
        super
      end
    end

    class TokenInvalid < AuthenticationError
      def initialize(message = "Access token is invalid", **options)
        super
      end
    end

    class SignatureInvalid < AuthenticationError
      def initialize(message = "OAuth signature validation failed", **options)
        super
      end
    end

    class SessionInitializationFailed < AuthenticationError
      def initialize(message = "Failed to initialize brokerage session", **options)
        super
      end
    end

    # Factory method to create appropriate authentication error with enhanced context
    def self.from_response(response, message: nil, context: {})
      error_details = extract_error_details(response)
      error_message = message || error_details[:message]

      # Add authentication-specific context
      auth_context = context.merge(
        response_status: response.status,
        request_id: error_details[:request_id],
        auth_header_present: response.respond_to?(:env) && response.env&.[](:request_headers)&.key?("Authorization"),
        endpoint: response.respond_to?(:env) && response.env&.[](:url)&.path
      ).compact

      # Determine specific error type based on response
      case response.status
      when 401
        if error_message&.include?("expired")
          TokenExpired.new(error_message, context: auth_context, response: response, details: error_details)
        elsif error_message&.include?("signature")
          SignatureInvalid.new(error_message, context: auth_context, response: response, details: error_details)
        elsif error_message&.include?("invalid")
          TokenInvalid.new(error_message, context: auth_context, response: response, details: error_details)
        else
          InvalidCredentials.new(error_message, context: auth_context, response: response, details: error_details)
        end
      when 403
        SessionInitializationFailed.new(error_message, context: auth_context, response: response, details: error_details)
      else
        new(error_message, context: auth_context, response: response, details: error_details)
      end
    end

    # Create authentication error with specific context
    def self.session_failed(message = "Session initialization failed", context: {})
      SessionInitializationFailed.with_context(message, context: context.merge(operation: "session_init"))
    end

    def self.credentials_invalid(message = "Invalid credentials", context: {})
      operation = context[:operation] || "authentication"
      InvalidCredentials.with_context(message, context: context.merge(operation: operation))
    end

    def self.token_expired(message = "Token has expired", context: {})
      TokenExpired.with_context(message, context: context.merge(operation: "token_validation"))
    end
  end
end
