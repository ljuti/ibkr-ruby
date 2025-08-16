# frozen_string_literal: true

require_relative "live_session_token"
require_relative "signature_generator"

module Ibkr
  module Oauth
    class Authenticator
      attr_reader :config, :http_client, :current_token

      def initialize(config:, http_client:)
        @config = config
        @http_client = http_client
        @signature_generator = Oauth::SignatureGenerator.new(config)
        @current_token = nil
      end

      # Authenticate and get live session token
      def authenticate
        @current_token = request_live_session_token
        @current_token.valid?(config.consumer_key)
      end

      # Check if currently authenticated with valid token
      def authenticated?
        @current_token&.valid?(config.consumer_key) || false
      end

      # Get current token, refreshing if necessary
      def token
        refresh_token_if_needed
        @current_token
      end

      # Alias for compatibility  
      def live_session_token
        token
      end

      # Logout and invalidate current session
      def logout
        return true unless authenticated?

        response = http_client.post("/v1/api/logout")
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
        
        body = { publish: true, compete: priority }
        response = http_client.post("/v1/api/iserver/auth/ssodh/init", body: body)

        if response.success?
          JSON.parse(response.body)
        else
          raise Ibkr::AuthenticationError::SessionInitializationFailed.from_response(response)
        end
      end

      # Ping the server to keep session alive
      def ping
        ensure_authenticated!
        
        response = http_client.post("/v1/api/tickle")
        if response.success?
          JSON.parse(response.body)
        else
          raise Ibkr::ApiError.from_response(response, message: "Ping failed")
        end
      end

      # Generate OAuth header for live session token request
      def oauth_header_for_authentication
        params = build_oauth_params_for_authentication
        format_oauth_header(params)
      end

      # Generate OAuth header for API requests
      def oauth_header_for_api_request(method:, url:, query: {}, body: {})
        ensure_authenticated!
        
        params = build_oauth_params_for_api(
          method: method,
          url: url,
          query: query,
          body: body,
          live_session_token: @current_token.token
        )
        
        format_oauth_header(params)
      end

      private

      def request_live_session_token
        response = http_client.post_raw("/v1/api/oauth/live_session_token")
        
        unless response.success?
          raise Ibkr::AuthenticationError.from_response(response)
        end

        parse_live_session_token_response(response)
      end

      def parse_live_session_token_response(response)
        data = JSON.parse(response.body)
        
        # Compute the actual token using Diffie-Hellman
        computed_token = @signature_generator.compute_live_session_token(
          data["diffie_hellman_response"]
        )
        
        Oauth::LiveSessionToken.new(
          computed_token,
          data["live_session_token_signature"],
          data["live_session_token_expiration"]
        )
      rescue JSON::ParserError => e
        raise Ibkr::AuthenticationError, "Invalid response format: #{e.message}"
      rescue KeyError => e
        raise Ibkr::AuthenticationError, "Missing required field in response: #{e.message}"
      end

      def build_oauth_params_for_authentication
        dh_challenge = @signature_generator.generate_dh_challenge
        
        params = {
          "oauth_consumer_key" => config.consumer_key,
          "oauth_nonce" => @signature_generator.generate_nonce,
          "oauth_timestamp" => @signature_generator.generate_timestamp,
          "oauth_token" => config.access_token,
          "oauth_signature_method" => "RSA-SHA256",
          "diffie_hellman_challenge" => dh_challenge
        }
        
        params["oauth_signature"] = URI.encode_www_form_component(
          @signature_generator.generate_rsa_signature(params)
        )
        params["realm"] = realm
        
        params
      end

      def build_oauth_params_for_api(method:, url:, query:, body:, live_session_token:)
        params = {
          "oauth_consumer_key" => config.consumer_key,
          "oauth_nonce" => @signature_generator.generate_nonce,
          "oauth_timestamp" => @signature_generator.generate_timestamp,
          "oauth_signature_method" => "HMAC-SHA256",
          "oauth_token" => config.access_token
        }
        
        params["oauth_signature"] = @signature_generator.generate_hmac_signature(
          method: method,
          url: url,
          params: params,
          query: query,
          body: body,
          live_session_token: live_session_token
        )
        params["realm"] = realm
        
        params
      end

      def format_oauth_header(params)
        params.sort.map { |k, v| "#{k}=\"#{v}\"" }.join(", ")
      end

      def realm
        config.production? ? "limited_poa" : "test_realm"
      end

      def ensure_authenticated!
        unless authenticated?
          raise Ibkr::AuthenticationError, "Not authenticated. Call authenticate first."
        end
      end

      def refresh_token_if_needed
        if @current_token&.expired?
          authenticate
        end
      end
    end
  end
end