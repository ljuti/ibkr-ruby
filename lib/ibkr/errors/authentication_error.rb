# frozen_string_literal: true

module Ibkr
  class AuthenticationError < BaseError
    def initialize(message = "Authentication failed", **options)
      super
    end

    # Specific authentication error types
    class InvalidCredentials < AuthenticationError
      def initialize(message = "Invalid credentials provided")
        super
      end
    end

    class TokenExpired < AuthenticationError
      def initialize(message = "Access token has expired")
        super
      end
    end

    class TokenInvalid < AuthenticationError
      def initialize(message = "Access token is invalid")
        super
      end
    end

    class SignatureInvalid < AuthenticationError
      def initialize(message = "OAuth signature validation failed")
        super
      end
    end

    class SessionInitializationFailed < AuthenticationError
      def initialize(message = "Failed to initialize brokerage session")
        super
      end
    end

    # Factory method to create appropriate authentication error
    def self.from_response(response, message: nil)
      error_details = extract_error_details(response)
      error_message = message || error_details[:message]

      # Determine specific error type based on response
      case response.status
      when 401
        if error_message&.include?("expired")
          TokenExpired.new(error_message)
        elsif error_message&.include?("signature")
          SignatureInvalid.new(error_message)
        elsif error_message&.include?("invalid")
          TokenInvalid.new(error_message)
        else
          InvalidCredentials.new(error_message)
        end
      when 403
        SessionInitializationFailed.new(error_message)
      else
        new(error_message, response: response)
      end
    end
  end
end
