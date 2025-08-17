# frozen_string_literal: true

module Ibkr
  class ApiError < BaseError
    def initialize(message = "API request failed", **options)
      super
    end

    # Specific API error types
    class BadRequest < ApiError
      def initialize(message = "Bad request - check your parameters")
        super
      end
    end

    class NotFound < ApiError
      def initialize(message = "Resource not found")
        super
      end
    end

    class ServerError < ApiError
      def initialize(message = "Server error occurred")
        super
      end
    end

    class ServiceUnavailable < ApiError
      def initialize(message = "Service temporarily unavailable")
        super
      end
    end

    class ValidationError < ApiError
      attr_reader :validation_errors

      def initialize(message = "Validation failed", validation_errors: [])
        super(message)
        @validation_errors = validation_errors
      end

      def to_h
        super.merge(validation_errors: validation_errors)
      end
    end

    # Factory method to create appropriate API error
    def self.from_response(response, message: nil)
      error_details = extract_error_details(response)
      error_message = message || error_details[:message] || default_message_for_status(response.status)

      case response.status
      when 400
        if error_details[:raw_response].is_a?(Hash) && error_details[:raw_response]["validationErrors"]
          ValidationError.new(
            error_message,
            validation_errors: error_details[:raw_response]["validationErrors"]
          )
        else
          BadRequest.new(error_message)
        end
      when 404
        NotFound.new(error_message)
      when 500..502
        ServerError.new(error_message)
      when 503
        ServiceUnavailable.new(error_message)
      else
        new(error_message, code: response.status, details: error_details, response: response)
      end
    end
  end
end
