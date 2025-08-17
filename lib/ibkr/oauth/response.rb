# frozen_string_literal: true

require "json"

module Ibkr
  module Oauth
    # Handles parsing and validation of OAuth-related API responses
    # Encapsulates OAuth response processing and validation logic
    class Response
      attr_reader :signature_generator

      def initialize(signature_generator:)
        @signature_generator = signature_generator
      end

      # Parse live session token response from OAuth authentication
      def parse_live_session_token(response)
        data = parse_json_response(response)

        # Compute the actual token using Diffie-Hellman
        computed_token = signature_generator.compute_live_session_token(
          data["diffie_hellman_response"]
        )

        LiveSessionToken.new(
          computed_token,
          data["live_session_token_signature"],
          data["live_session_token_expiration"]
        )
      end

      # Parse general JSON response with error handling
      def parse_json_response(response)
        validate_response_success!(response)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Ibkr::AuthenticationError, "Invalid response format: #{e.message}"
      end

      private

      def validate_response_success!(response)
        return if response.success?

        raise Ibkr::AuthenticationError.from_response(response)
      end

      def validate_required_fields!(data, required_fields)
        missing_fields = required_fields.reject { |field| data.key?(field) }
        return if missing_fields.empty?

        raise Ibkr::AuthenticationError,
          "Missing required fields in response: #{missing_fields.join(", ")}"
      end
    end
  end
end
