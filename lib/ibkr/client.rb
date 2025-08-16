# frozen_string_literal: true

require_relative "oauth"
require_relative "services/accounts"

module Ibkr
  class Client
    attr_reader :config, :account_id

    def initialize(config: nil, live: false)
      @config = config || Ibkr.configuration.dup
      @live = live
      
      # Set environment based on live parameter for backward compatibility
      @config.environment = live ? "production" : "sandbox"
      
      @oauth_client = nil
      @account_id = nil
      @services = {}
    end

    # Authentication methods
    def authenticate
      oauth_client.authenticate
    end

    def authenticated?
      oauth_client.authenticated?
    end

    def logout
      oauth_client.logout
    end

    # Session management
    def initialize_session(priority: false)
      oauth_client.initialize_session(priority: priority)
    end

    def ping
      oauth_client.ping
    end

    # Account management
    def set_account_id(account_id)
      @account_id = account_id
    end

    def account_id
      @account_id
    end

    # Service accessors
    def accounts
      @services[:accounts] ||= Accounts.new(self)
    end
    
    # Public accessor for oauth_client (for testing)
    def oauth_client
      @oauth_client ||= Oauth.new(config: @config, live: @live)
    end

    # HTTP methods (delegated to OAuth client)
    def get(path, **options)
      oauth_client.get(path, **options)
    end

    def post(path, **options)
      oauth_client.post(path, **options)
    end

    def put(path, **options)
      oauth_client.put(path, **options)
    end

    def delete(path, **options)
      oauth_client.delete(path, **options)
    end

    # Configuration accessors
    def environment
      @config.environment
    end

    def sandbox?
      @config.sandbox?
    end

    def production?
      @config.production?
    end

  end
end