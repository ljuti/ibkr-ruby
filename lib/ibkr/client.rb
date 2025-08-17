# frozen_string_literal: true

require_relative "oauth"
require_relative "services/accounts"

module Ibkr
  class Client
    attr_reader :config, :active_account_id, :available_accounts

    def initialize(default_account_id: nil, config: nil, live: false)
      @default_account_id = default_account_id&.freeze
      @active_account_id = nil
      @available_accounts = []
      @config = config || Ibkr.configuration.dup
      @live = live
      
      # Set environment based on live parameter for backward compatibility
      @config.environment = live ? "production" : "sandbox"
      
      @oauth_client = nil
      @services = {}
    end

    # Authentication methods
    def authenticate
      # 1. Perform OAuth authentication
      result = oauth_client.authenticate
      
      if result
        # 2. Fetch available accounts after successful authentication
        @available_accounts = fetch_available_accounts
        
        # 3. Set active account (default or first available)
        @active_account_id = @default_account_id || @available_accounts.first
        
        # Validate the active account is actually available
        if @active_account_id && !@available_accounts.include?(@active_account_id)
          @active_account_id = @available_accounts.first
        end
      end
      
      result
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

    # Multi-account management
    def set_active_account(account_id)
      ensure_authenticated!
      unless @available_accounts.include?(account_id)
        raise ArgumentError, "Account #{account_id} not available. Available accounts: #{@available_accounts.join(', ')}"
      end
      @active_account_id = account_id
      
      # Clear cached services so they pick up the new account
      @services.clear
    end
    
    # Legacy alias for backwards compatibility
    def account_id
      @active_account_id
    end
    
    # Legacy method for backwards compatibility (with validation)
    def set_account_id(account_id)
      set_active_account(account_id)
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

    private

    def fetch_available_accounts
      # In a real implementation, this would call an IBKR API endpoint
      # For now, we'll simulate this based on the default account or return a default
      if @default_account_id
        [@default_account_id]
      else
        # Simulate fetching from IBKR API - in reality this would be:
        # response = oauth_client.get("/v1/api/brokerage/accounts")
        # response["accounts"].map { |acc| acc["id"] }
        ["DU123456"]  # Default sandbox account
      end
    rescue StandardError
      # If fetching accounts fails, return default account or empty array
      @default_account_id ? [@default_account_id] : []
    end

    def ensure_authenticated!
      unless authenticated?
        raise StandardError, "Not authenticated. Call authenticate first."
      end
    end

  end
end