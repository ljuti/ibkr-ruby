# frozen_string_literal: true

require_relative "oauth/authenticator"
require_relative "oauth/live_session_token"
require_relative "oauth/signature_generator"
require_relative "oauth/response"
require_relative "oauth/headers"
require_relative "oauth/parameters"
require_relative "oauth/signatures"
require_relative "http/client"

module Ibkr
  # OAuth module namespace
  module Oauth
    # Main OAuth interface - coordinates authentication flow
    class Client
      attr_reader :config, :http_client, :authenticator, :live

      def initialize(config: nil, live: nil)
        @config = config || Ibkr.configuration
        # Store live mode - infer from config if not explicitly passed
        @live = live.nil? ? @config.production? : live
        # Don't validate during initialization - validate when needed

        @http_client = Ibkr::Http::Client.new(config: @config)
        @authenticator = Oauth::Authenticator.new(config: @config, http_client: @http_client)

        # Update http client to use authenticator
        @http_client.authenticator = @authenticator
      end

      # Authenticate with IBKR
      def authenticate
        @authenticator.authenticate
      end

      # Check authentication status
      def authenticated?
        @authenticator.authenticated?
      end

      # Get current live session token
      def token
        @authenticator.token
      end

      # Get live session token (alias for compatibility)
      def live_session_token
        @authenticator.live_session_token
      end

      # Logout
      def logout
        @authenticator.logout
      end

      # Initialize brokerage session
      def initialize_session(priority: false)
        @authenticator.initialize_session(priority: priority)
      end

      # Keep session alive
      def ping
        @authenticator.ping
      end

      # Delegate HTTP methods to authenticated client
      def get(path, params: {}, headers: {})
        @http_client.get(path, params: params, headers: headers)
      end

      def post(path, body: {}, headers: {})
        @http_client.post(path, body: body, headers: headers)
      end

      def put(path, body: {}, headers: {})
        @http_client.put(path, body: body, headers: headers)
      end

      def delete(path, headers: {})
        @http_client.delete(path, headers: headers)
      end

      # Configuration helpers
      def sandbox?
        @config.sandbox?
      end

      def production?
        @config.production?
      end

      def environment
        @config.environment
      end
    end

    # Add module methods to make Oauth.new work
    def self.new(**kwargs)
      Client.new(**kwargs)
    end
  end
end
