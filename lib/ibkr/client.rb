# frozen_string_literal: true

require_relative "oauth"
require_relative "accounts"
require_relative "chainable_accounts_proxy"
require_relative "websocket"
require_relative "account_manager"
require_relative "http_delegator"
require_relative "websocket_facade"
require_relative "configuration_delegator"

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
    include HttpDelegator
    include ConfigurationDelegator

    attr_reader :config, :default_account_id, :live

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
      @config = config || Ibkr.configuration.dup
      @live = live

      @config.environment = live ? "production" : "sandbox"

      @oauth_client = nil
      @services = {}
      @account_manager = nil
      @websocket_facade = nil
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

      # 2. Set up account access if authentication succeeded
      account_manager.discover_accounts if result

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
      account_manager.set_active_account(account_id)
      
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
      account_manager.active_account_id
    end

    # Get the list of available accounts.
    #
    # @return [Array<String>] List of available account IDs
    def available_accounts
      account_manager.available_accounts
    end

    # Get the currently active account ID (alias for account_id).
    #
    # @return [String, nil] The active account ID, or nil if not authenticated
    def active_account_id
      account_id
    end

    # Check if client is in live mode
    alias_method :live_mode?, :live

    # Service accessors
    def accounts
      @services[:accounts] ||= Accounts.new(self)
    end


    # Fluent interface methods

    # Authenticate and return self for chaining
    def authenticate!
      authenticate
      self
    end

    # Switch account and return self for chaining
    def with_account(account_id)
      set_active_account(account_id)
      self
    end

    # Alias for accounts service that returns chainable accounts proxy
    def portfolio
      ChainableAccountsProxy.new(self)
    end

    # Chainable version of accounts service
    def accounts_fluent
      ChainableAccountsProxy.new(self)
    end

    # WebSocket facade for real-time operations.
    #
    # @return [Ibkr::WebSocketFacade] WebSocket facade instance
    def websocket_facade
      @websocket_facade ||= WebSocketFacade.new(self)
    end

    # WebSocket client accessor (delegates to facade).
    #
    # @return [Ibkr::WebSocket::Client] WebSocket client instance
    def websocket
      websocket_facade.websocket
    end

    # Streaming interface for WebSocket operations.
    #
    # @return [Ibkr::WebSocket::Streaming] Streaming interface
    def streaming
      websocket_facade.streaming
    end

    # Market data interface for real-time data.
    #
    # @return [Ibkr::WebSocket::MarketData] Market data interface
    def real_time_data
      websocket_facade.real_time_data
    end

    # Fluent interface for WebSocket connection.
    #
    # @return [self] Returns self for method chaining
    def with_websocket
      websocket.connect
      self
    end

    # Stream market data (fluent interface).
    #
    # @param symbols [Array<String>, String] Symbols to subscribe to
    # @param fields [Array<String>] Data fields to receive (default: ["price"])
    # @return [self] Returns self for method chaining
    def stream_market_data(*symbols, fields: ["price"])
      websocket.subscribe_to_market_data(symbols.flatten, fields)
      self
    end

    # Stream portfolio updates (fluent interface).
    #
    # @param account_id [String, nil] Account ID (uses current account if nil)
    # @return [self] Returns self for method chaining
    def stream_portfolio(account_id = nil)
      websocket.subscribe_to_portfolio_updates(account_id || active_account_id)
      self
    end

    # Stream order status updates (fluent interface).
    #
    # @param account_id [String, nil] Account ID (uses current account if nil)
    # @return [self] Returns self for method chaining
    def stream_orders(account_id = nil)
      websocket.subscribe_to_order_status(account_id || active_account_id)
      self
    end

    private

    def oauth_client
      @oauth_client ||= Oauth.new(config: @config, live: @live)
    end

    # Get the account manager instance (lazy-loaded).
    #
    # @return [Ibkr::AccountManager] Account manager instance
    def account_manager
      @account_manager ||= AccountManager.new(oauth_client, default_account_id: @default_account_id)
    end

    # Abstract method required by HttpDelegator module.
    #
    # @return [Ibkr::Oauth::Client] The HTTP client that handles requests
    def http_client
      oauth_client
    end

    # Abstract method required by ConfigurationDelegator module.
    #
    # @return [Ibkr::Configuration] The configuration object
    def config_object
      @config
    end

  end
end
