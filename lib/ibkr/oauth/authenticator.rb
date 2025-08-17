# frozen_string_literal: true

require_relative "live_session_token"
require_relative "signature_generator"
require_relative "response"
require_relative "headers"

module Ibkr
  module Oauth
    class Authenticator
      attr_reader :config, :http_client, :signature_generator, :response_parser, :header_factory
      attr_accessor :current_token

      def initialize(config:, http_client:)
        @config = config
        @http_client = http_client
        @signature_generator = Oauth::SignatureGenerator.new(config)
        @response_parser = Oauth::Response.new(signature_generator: @signature_generator)
        @header_factory = Oauth::Headers.new(config: config, signature_generator: @signature_generator)
        @current_token = nil
      end

      # Authenticate and get live session token
      def authenticate
        @current_token = request_live_session_token
        current_token.valid?(config.consumer_key)
      end

      # Check if currently authenticated with valid token
      def authenticated?
        @current_token&.valid?(config.consumer_key) || false
      end

      # Get current token, refreshing if necessary
      def token
        refresh_token_if_needed
        current_token
      end

      # Alias for compatibility
      def live_session_token
        token
      end

      # Logout and invalidate current session
      def logout
        return true unless authenticated?

        response = http_client.post_raw("/v1/api/logout")
        if response.success?
          @current_token = nil
          true
        else
          raise Ibkr::ApiError.from_response(response, message: "Logout failed")
        end
      end

      # Initialize brokerage session
      def initialize_session(priority: false)
        ensure_authenticated!

        body = {publish: true, compete: priority}
        response = http_client.post_raw("/v1/api/iserver/auth/ssodh/init", body: body)

        if response.success?
          JSON.parse(response.body)
        else
          raise Ibkr::AuthenticationError::SessionInitializationFailed.from_response(response)
        end
      end

      # Ping the server to keep session alive
      def ping
        ensure_authenticated!

        response = http_client.post_raw("/v1/api/tickle")
        if response.success?
          JSON.parse(response.body)
        else
          raise Ibkr::ApiError.from_response(response, message: "Ping failed")
        end
      end

      # Generate OAuth header for live session token request
      def oauth_header_for_authentication
        header_factory.create_authentication_header
      end

      # Generate OAuth header for API requests
      def oauth_header_for_api_request(method:, url:, query: {}, body: {})
        ensure_authenticated!

        header_factory.create_api_header(
          method: method,
          url: url,
          query: query,
          body: body,
          live_session_token: @current_token.token
        )
      end

      private

      def request_live_session_token
        response = http_client.post_raw("/v1/api/oauth/live_session_token")

        unless response.success?
          raise Ibkr::AuthenticationError.from_response(response)
        end

        response_parser.parse_live_session_token(response)
      end

      # Private methods for internal state management
      # Complex parameter building and response parsing have been
      # extracted to dedicated classes following SRP

      def ensure_authenticated!
        unless authenticated?
          raise Ibkr::AuthenticationError, "Not authenticated. Call authenticate first."
        end
      end

      def refresh_token_if_needed
        if @current_token.nil? || @current_token.expired?
          authenticate
        end
      end
    end
  end
end
