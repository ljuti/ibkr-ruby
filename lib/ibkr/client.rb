# frozen_string_literal: true

require_relative "oauth"
require_relative "accounts"
require_relative "chainable_accounts_proxy"
require_relative "websocket"

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
    attr_reader :config, :active_account_id, :available_accounts, :default_account_id, :live

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
        raise Ibkr::ApiError.account_not_found(
          account_id,
          context: {
            available_accounts: @available_accounts,
            operation: "set_active_account"
          }
        )
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
    alias_method :account_id, :active_account_id

    # Check if client is in live mode
    alias_method :live_mode?, :live

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

    # Test-specific methods for dependency injection
    # These methods are used by tests to inject mock objects and set up test scenarios
    # They should only be used in test environments

    # Allow test injection of OAuth client
    attr_writer :oauth_client

    # Allow test setup of available accounts (used after authentication in real scenarios)
    def set_available_accounts(accounts)
      @available_accounts = accounts.freeze
    end

    # Allow test setup of active account directly (bypassing normal validation)
    def set_active_account_for_test(account_id)
      @active_account_id = account_id
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

    # WebSocket accessor (lazy-loaded)
    #
    # Provides real-time streaming capabilities for market data, portfolio updates,
    # and order status. The WebSocket client is created on first access and
    # integrates with the existing authentication system.
    #
    # @return [Ibkr::WebSocket::Client] WebSocket client instance
    #
    # @example Basic usage
    #   websocket = client.websocket
    #   websocket.connect
    #   websocket.subscribe_market_data(["AAPL"], ["price"])
    #
    # @example Fluent interface
    #   client.websocket
    #     .connect
    #     .subscribe_market_data(["AAPL"], ["price"])
    #     .subscribe_portfolio
    #
    def websocket
      @websocket ||= WebSocket::Client.new(self)
    end

    # Streaming interface for WebSocket operations
    def streaming
      @streaming ||= WebSocket::Streaming.new(websocket)
    end

    # Market data interface for real-time data
    def real_time_data
      @real_time_data ||= WebSocket::MarketData.new(websocket)
    end

    # Fluent interface for WebSocket connection
    #
    # Connects to WebSocket and returns self for method chaining.
    # Useful for fluent interface workflows.
    #
    # @return [self] Returns self for method chaining
    #
    # @example
    #   client.with_websocket.stream_market_data("AAPL")
    #
    def with_websocket
      websocket.connect
      self
    end

    # Stream market data (fluent interface)
    #
    # Connects to WebSocket and subscribes to market data for specified symbols.
    # Returns self for method chaining.
    #
    # @param symbols [Array<String>, String] Symbols to subscribe to
    # @param fields [Array<String>] Data fields to receive (default: ["price"])
    # @return [self] Returns self for method chaining
    #
    # @example
    #   client.stream_market_data("AAPL")
    #   client.stream_market_data(["AAPL", "MSFT"], ["price", "volume"])
    #
    def stream_market_data(*symbols, fields: ["price"])
      websocket.subscribe_to_market_data(symbols.flatten, fields)
      self
    end

    # Stream portfolio updates (fluent interface)
    #
    # Connects to WebSocket and subscribes to portfolio updates for the current account.
    # Returns self for method chaining.
    #
    # @param account_id [String, nil] Account ID (uses current account if nil)
    # @return [self] Returns self for method chaining
    #
    # @example
    #   client.stream_portfolio
    #   client.stream_portfolio("DU789012")
    #
    def stream_portfolio(account_id = nil)
      websocket.subscribe_to_portfolio_updates(account_id || @active_account_id)
      self
    end

    # Stream order status updates (fluent interface)
    #
    # Connects to WebSocket and subscribes to order status updates for the current account.
    # Returns self for method chaining.
    #
    # @param account_id [String, nil] Account ID (uses current account if nil)
    # @return [self] Returns self for method chaining
    #
    # @example
    #   client.stream_orders
    #   client.stream_orders("DU789012")
    #
    def stream_orders(account_id = nil)
      websocket.subscribe_to_order_status(account_id || @active_account_id)
      self
    end

    private

    def fetch_available_accounts
      # Ensure we have an authenticated brokerage session
      unless oauth_client.authenticated?
        raise Ibkr::AuthenticationError.credentials_invalid(
          "Client must be authenticated before fetching accounts",
          context: {operation: "fetch_accounts", default_account_id: @default_account_id}
        )
      end

      # Initialize brokerage session if needed
      oauth_client.initialize_session(priority: true)

      # Fetch available accounts from IBKR API
      response = oauth_client.get("/v1/api/iserver/accounts")

      # Extract account IDs from the response
      response["accounts"] || []

      # Return account IDs array
    rescue Ibkr::BaseError
      # Re-raise IBKR-specific errors (they have useful context)
      raise
    rescue => e
      # If fetching accounts fails for other reasons, fall back gracefully
      # In production, this would be logged as a warning
      if @default_account_id
        [@default_account_id]
      else
        raise Ibkr::ApiError.with_context(
          "Failed to fetch available accounts: #{e.message}",
          context: {
            operation: "fetch_accounts",
            default_account_id: @default_account_id,
            error_class: e.class.name,
            original_error: e.message
          }
        )
      end
    end

    def ensure_authenticated!
      unless authenticated?
        raise Ibkr::AuthenticationError.credentials_invalid(
          "Not authenticated. Call authenticate first.",
          context: {
            operation: "ensure_authenticated",
            default_account_id: @default_account_id,
            available_accounts: @available_accounts
          }
        )
      end
    end
  end
end
