# frozen_string_literal: true

module Ibkr
  class ApiError < BaseError
    def initialize(message = "API request failed", **options)
      super
    end

    # Specific API error types
    class BadRequest < ApiError
      def initialize(message = "Bad request - check your parameters", **options)
        super
      end
    end

    class NotFound < ApiError
      def initialize(message = "Resource not found", **options)
        super
      end
    end

    class ServerError < ApiError
      def initialize(message = "Server error occurred", **options)
        super
      end
    end

    class ServiceUnavailable < ApiError
      def initialize(message = "Service temporarily unavailable", **options)
        super
      end
    end

    class ValidationError < ApiError
      attr_reader :validation_errors

      def initialize(message = "Validation failed", validation_errors: [], **options)
        super(message, **options)
        @validation_errors = validation_errors
      end

      def to_h
        super.merge(validation_errors: validation_errors)
      end
    end

    # Factory method to create appropriate API error with enhanced context
    def self.from_response(response, message: nil, context: {})
      error_details = extract_error_details(response)
      error_message = message || error_details[:message] || default_message_for_status(response.status)

      # Add API-specific context
      api_context = context.merge(
        endpoint: response.respond_to?(:env) && response.env&.[](:url)&.path,
        method: response.respond_to?(:env) && response.env&.[](:method)&.to_s&.upcase,
        response_status: response.status,
        response_time: response.respond_to?(:env) && response.env&.[](:duration),
        request_id: error_details[:request_id],
        user_agent: response.respond_to?(:env) && response.env&.[](:request_headers)&.[]("User-Agent")
      ).compact

      case response.status
      when 400
        if error_details[:raw_response].is_a?(Hash) && error_details[:raw_response]["validationErrors"]
          ValidationError.new(
            error_message,
            validation_errors: error_details[:raw_response]["validationErrors"],
            context: api_context,
            response: response,
            details: error_details
          )
        else
          BadRequest.new(error_message, context: api_context, response: response, details: error_details)
        end
      when 404
        NotFound.new(error_message, context: api_context, response: response, details: error_details)
      when 500..502
        ServerError.new(error_message, context: api_context, response: response, details: error_details)
      when 503
        ServiceUnavailable.new(error_message, context: api_context, response: response, details: error_details)
      else
        new(error_message, code: response.status, context: api_context, details: error_details, response: response)
      end
    end

    # Create API error with specific context for different scenarios
    def self.account_not_found(account_id, context: {})
      operation = context[:operation] || "account_lookup"
      NotFound.with_context(
        "Account #{account_id} not found or not accessible",
        context: context.merge(account_id: account_id, operation: operation)
      )
    end

    def self.validation_failed(validation_errors, context: {})
      ValidationError.new(
        "Request validation failed",
        validation_errors: validation_errors,
        context: context.merge(operation: "request_validation")
      )
    end

    def self.server_error(message = "Server error occurred", context: {})
      ServerError.with_context(message, context: context.merge(operation: "server_request"))
    end
  end
end
