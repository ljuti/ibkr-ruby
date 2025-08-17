# frozen_string_literal: true

require_relative "oauth"
require_relative "services/accounts"

module Ibkr
  # Main client for Interactive Brokers Web API access.
  #
  # Supports both single and multi-account workflows through a hybrid approach:
  # - Single Account: Specify default_account_id at initialization
  # - Multi-Account: Don't specify default_account_id, switch accounts after authentication
  #
  # @example Single Account Workflow (Recommended)
  #   client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
  #   client.authenticate  # Active account automatically set to DU123456
  #   summary = client.accounts.summary
  #
  # @example Multi-Account Workflow
  #   client = Ibkr::Client.new(live: false)
  #   client.authenticate  # Active account set to first available
  #   client.set_active_account("DU789012")  # Switch to different account
  #   summary = client.accounts.summary  # Uses DU789012
  #
  # @example Account Management
  #   puts "Available: #{client.available_accounts}"
  #   puts "Active: #{client.account_id}"
  #   client.set_active_account("DU555555")  # Switch accounts
  #
  class Client
    attr_reader :config, :active_account_id, :available_accounts

    # Initialize a new IBKR client.
    #
    # @param default_account_id [String, nil] Account ID to use by default after authentication.
    #   If provided, this account will be automatically set as active after successful authentication.
    #   If nil, the first available account will be used.
    # @param config [Ibkr::Configuration, nil] Custom configuration object. Uses global config if nil.
    # @param live [Boolean] Whether to use production (true) or sandbox (false) environment.
    #
    # @example Single account setup
    #   client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
    #
    # @example Multi-account setup
    #   client = Ibkr::Client.new(live: false)  # Will use first available account
    #
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

    # Authenticate with IBKR and set up account access.
    #
    # This method performs OAuth authentication and automatically sets up account access:
    # 1. Performs OAuth authentication with IBKR
    # 2. Fetches list of available accounts
    # 3. Sets active account to default_account_id (if provided) or first available account
    #
    # @return [Boolean] true if authentication succeeded, false otherwise
    #
    # @example
    #   client = Ibkr::Client.new(default_account_id: "DU123456")
    #   success = client.authenticate
    #   puts "Active account: #{client.account_id}" if success
    #
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

    # Switch to a different account.
    #
    # Changes the active account for all subsequent API operations. The account
    # must be in the list of available accounts (accessible via available_accounts).
    # This clears the service cache to ensure clean state for the new account.
    #
    # @param account_id [String] The account ID to switch to
    # @raise [ArgumentError] if the account is not available
    # @raise [StandardError] if not authenticated
    #
    # @example
    #   client.set_active_account("DU789012")
    #   puts "Now using: #{client.account_id}"
    #
    def set_active_account(account_id)
      ensure_authenticated!
      unless @available_accounts.include?(account_id)
        raise ArgumentError, "Account #{account_id} not available. Available accounts: #{@available_accounts.join(", ")}"
      end
      @active_account_id = account_id

      # Clear cached services so they pick up the new account
      @services.clear
    end

    # Get the currently active account ID.
    #
    # @return [String, nil] The active account ID, or nil if not authenticated
    #
    # @example
    #   puts "Current account: #{client.account_id}"
    #
    def account_id
      @active_account_id
    end

    # Legacy method for setting account ID (deprecated).
    #
    # @deprecated Use {#set_active_account} instead
    # @param account_id [String] The account ID to switch to
    #
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
    rescue
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
