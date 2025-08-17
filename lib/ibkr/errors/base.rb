# frozen_string_literal: true

module Ibkr
  class BaseError < StandardError
    attr_reader :code, :details, :response

    def initialize(message = nil, code: nil, details: nil, response: nil)
      super(message)
      @code = code
      @details = details
      @response = response
    end

    # Extract useful information from HTTP response
    def self.from_response(response, message: nil)
      details = extract_error_details(response)
      error_message = message || details[:message] || default_message_for_status(response.status)

      new(
        error_message,
        code: details[:code] || response.status,
        details: details,
        response: response
      )
    end

    def to_h
      {
        error: self.class.name,
        message: message,
        code: code,
        details: details
      }.compact
    end

    class << self
      private

      def extract_error_details(response)
        return {} unless response&.body

        begin
          parsed = JSON.parse(response.body)
          {
            message: parsed["error"] || parsed["message"] || parsed["errorMessage"],
            code: parsed["code"] || parsed["errorCode"],
            request_id: parsed["requestId"] || response.headers["X-Request-ID"],
            raw_response: parsed
          }
        rescue JSON::ParserError
          {
            message: response.body.to_s.strip[0, 200], # First 200 chars
            raw_response: response.body
          }
        end
      end

      def default_message_for_status(status)
        case status
        when 400
          "Bad request - invalid parameters"
        when 401
          "Authentication failed"
        when 403
          "Forbidden - insufficient permissions"
        when 404
          "Resource not found"
        when 429
          "Rate limit exceeded"
        when 500..599
          "Server error occurred"
        else
          "HTTP request failed with status #{status}"
        end
      end
    end
  end
end
