# frozen_string_literal: true

require_relative "parameters"
require_relative "signatures"

module Ibkr
  module Oauth
    # Creates OAuth headers for authentication and API requests
    # Encapsulates OAuth header generation logic
    class Headers
      attr_reader :config, :signature_generator

      def initialize(config:, signature_generator:)
        @config = config
        @signature_generator = signature_generator
      end

      # Create OAuth header for authentication requests
      def create_authentication_header
        builder = AuthenticationParameters.new(
          config: config,
          signature_generator: signature_generator
        )

        params = builder.build_complete
        format_oauth_header(params)
      end

      # Create OAuth header for API requests
      def create_api_header(method:, url:, live_session_token:, query: {}, body: {})
        request_params = {
          method: method,
          url: url,
          query: query,
          body: body,
          live_session_token: live_session_token
        }

        builder = ApiParameters.new(
          config: config,
          signature_generator: signature_generator,
          request_params: request_params
        )

        params = builder.build_complete
        format_oauth_header(params)
      end

      private

      # Format OAuth parameters as header string
      # Sorts parameters alphabetically for consistent output
      def format_oauth_header(params)
        params.sort.map { |k, v| "#{k}=\"#{v}\"" }.join(", ")
      end
    end
  end
end
