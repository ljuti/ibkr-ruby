# frozen_string_literal: true

require "securerandom"
require "base64"
require "json"
require "cgi"
require "openssl"
require_relative "configuration"

module Ibkr
  module WebSocket
    # WebSocket authentication handler for IBKR API
    #
    # Manages WebSocket-specific authentication using existing OAuth credentials
    # from the main IBKR client. Follows IBKR's documented WebSocket flow:
    # 1. Get session token from /tickle endpoint
    # 2. Include OAuth token in WebSocket URL
    # 3. Send session token as authentication message
    #
    # Based on IBKR WebSocket API requirements:
    # - Uses /tickle endpoint to get session token
    # - Includes OAuth token in WebSocket URL
    # - Sends session token for WebSocket authentication
    #
    class Authentication
      attr_reader :session_token, :session_data

      # @param ibkr_client [Ibkr::Client] The authenticated IBKR client
      def initialize(ibkr_client)
        @ibkr_client = ibkr_client
        @session_token = nil
        @session_data = nil
      end

      # Check if WebSocket client is authenticated
      #
      # @return [Boolean] True if authenticated and session token is valid
      def authenticated?
        return false unless @session_token

        @ibkr_client.authenticated?
      end

      # Get session token from /tickle endpoint and prepare WebSocket auth
      #
      # Follows IBKR's documented WebSocket authentication flow:
      # 1. Get session information from /tickle endpoint
      # 2. Extract session token for WebSocket authentication
      #
      # @return [String] Session token for WebSocket authentication
      # @raise [AuthenticationError] If authentication fails
      def authenticate_websocket
        ensure_main_client_authenticated!

        # Get session information from /tickle endpoint
        get_session_token_from_tickle

        # Return the session token as JSON string for WebSocket auth
        {"session" => @session_token}.to_json
      end

      # Alias for compatibility
      alias_method :current_token, :session_token

      # Force refresh of session token from /tickle
      #
      # @return [String] New session token
      def refresh_token!
        ensure_main_client_authenticated!
        get_session_token_from_tickle
        @session_token
      end

      # Get WebSocket endpoint URL
      # For cookie-based auth, we don't include OAuth token in URL
      #
      # @return [String] WebSocket endpoint URL
      def websocket_endpoint
        Configuration.websocket_endpoint(@ibkr_client.environment)
      end

      # Get authentication headers for WebSocket connection
      #
      # @return [Hash] Headers to include in WebSocket connection
      def connection_headers
        ensure_main_client_authenticated!

        # Always get fresh session token for new connections
        get_session_token_from_tickle

        cookie_value = "api=#{@session_token}"

        Configuration.default_headers(Ibkr::VERSION).merge(
          "Cookie" => cookie_value
        )
      end

      # Check if current session token is valid
      #
      # @return [Boolean] True if session token exists
      def token_valid?
        !@session_token.nil?
      end

      # Get session expiration info (if available from session data)
      #
      # @return [Integer, nil] Seconds until expiration, or nil if unknown
      def token_expires_in
        return nil unless @session_data&.dig("ssoExpires")

        expires_at = @session_data["ssoExpires"]
        return nil unless expires_at.is_a?(Integer)

        expires_at - Time.now.to_i
      end

      # Handle authentication response from WebSocket server
      #
      # @param response [Hash] Authentication response message
      # @return [Boolean] True if authentication was successful
      # @raise [AuthenticationError] If authentication failed
      def handle_auth_response(response)
        case response[:status] || response["status"]
        when "success", "authenticated"
          true
        when "error", "failed"
          raise AuthenticationError.invalid_credentials(
            context: {
              error_code: response[:error] || response["error"],
              message: response[:message] || response["message"] || "Authentication failed",
              response: response
            }
          )
        else
          raise AuthenticationError.invalid_credentials(
            context: {
              unexpected_status: response[:status] || response["status"],
              response: response
            }
          )
        end
      end

      private

      # Get session token from /tickle endpoint
      #
      # Makes a request to /tickle endpoint to get session information
      # and extracts the session token needed for WebSocket authentication
      def get_session_token_from_tickle
        # Use the existing ping method which calls /tickle
        response = @ibkr_client.ping

        if response && response["session"]
          @session_data = response
          @session_token = response["session"]
        else
          raise AuthenticationError.invalid_credentials(
            context: {
              operation: "tickle_session_token",
              response: response
            }
          )
        end
      rescue => e
        raise AuthenticationError.invalid_credentials(
          context: {
            operation: "tickle_session_token",
            error: e.message
          }
        )
      end

      # Ensure the main IBKR client is authenticated
      #
      # @raise [AuthenticationError] If client is not authenticated
      def ensure_main_client_authenticated!
        unless @ibkr_client.authenticated?
          raise AuthenticationError.not_authenticated(
            context: {
              operation: "websocket_authentication_check",
              client_state: "not_authenticated"
            }
          )
        end
      end
    end
  end
end
