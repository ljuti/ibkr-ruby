# frozen_string_literal: true

module Ibkr
  # Manages account discovery, validation, and switching operations.
  #
  # This class encapsulates all account-related logic, providing a clean
  # separation of concerns from the main Client class. It handles:
  # - Fetching available accounts from the API
  # - Validating account access
  # - Managing active account state
  # - Account switching with proper validation
  #
  # @example
  #   manager = AccountManager.new(oauth_client, default_account_id: "DU123456")
  #   accounts = manager.discover_accounts
  #   manager.set_active_account("DU789012") if accounts.include?("DU789012")
  #
  class AccountManager
    attr_reader :available_accounts, :active_account_id, :default_account_id

    # Initialize account manager.
    #
    # @param oauth_client [Ibkr::Oauth::Client] Authenticated OAuth client
    # @param default_account_id [String, nil] Preferred account ID to use after discovery
    def initialize(oauth_client, default_account_id: nil)
      @oauth_client = oauth_client
      @default_account_id = default_account_id&.freeze
      @available_accounts = []
      @active_account_id = nil
    end

    # Discover and setup accounts after authentication.
    #
    # Fetches available accounts from the API and sets the active account
    # to either the default account (if available) or the first account found.
    #
    # @return [Array<String>] List of available account IDs
    # @raise [Ibkr::AuthenticationError] if not authenticated
    # @raise [Ibkr::ApiError] if account discovery fails
    def discover_accounts
      ensure_authenticated!

      @available_accounts = fetch_accounts_from_api
      @active_account_id = determine_active_account

      @available_accounts
    end

    # Set up test accounts directly (for testing).
    #
    # @param accounts [Array<String>] List of account IDs
    def setup_test_accounts(accounts)
      @available_accounts = accounts.freeze
    end

    # Set up test active account directly (for testing).
    #
    # @param account_id [String] Account ID to set as active
    def setup_test_active_account(account_id)
      @active_account_id = account_id
    end

    # Switch to a different account.
    #
    # @param account_id [String] The account ID to switch to
    # @raise [ArgumentError] if the account is not available
    # @raise [Ibkr::AuthenticationError] if not authenticated
    def set_active_account(account_id)
      ensure_authenticated!
      validate_account_available!(account_id)

      @active_account_id = account_id
    end

    # Check if an account is available.
    #
    # @param account_id [String] The account ID to check
    # @return [Boolean] true if the account is available
    def account_available?(account_id)
      @available_accounts.include?(account_id)
    end

    # Reset account state (used when authentication is lost).
    def reset!
      @available_accounts = []
      @active_account_id = nil
    end

    private

    # Fetch available accounts from the IBKR API.
    #
    # @return [Array<String>] List of account IDs
    # @raise [Ibkr::ApiError] if fetching fails
    def fetch_accounts_from_api
      # Initialize brokerage session if needed
      @oauth_client.initialize_session(priority: true)

      # Fetch available accounts from IBKR API
      response = @oauth_client.get("/v1/api/iserver/accounts")
      response["accounts"] || []
    rescue Ibkr::BaseError
      # Re-raise IBKR-specific errors (they have useful context)
      raise
    rescue => e
      handle_fetch_error(e)
    end

    # Handle errors during account fetching with fallback logic.
    #
    # @param error [Exception] The original error
    # @return [Array<String>] Fallback account list or raises error
    # @raise [Ibkr::ApiError] if no fallback is possible
    def handle_fetch_error(error)
      # If we have a default account, use it as fallback
      return [@default_account_id] if @default_account_id

      # Otherwise, raise a descriptive error
      raise Ibkr::ApiError.with_context(
        "Failed to fetch available accounts: #{error.message}",
        context: {
          operation: "fetch_accounts",
          default_account_id: @default_account_id,
          error_class: error.class.name,
          original_error: error.message
        }
      )
    end

    # Determine which account should be active after discovery.
    #
    # @return [String, nil] The account ID to use as active
    def determine_active_account
      # Prefer default account if it's available
      if @default_account_id && @available_accounts.include?(@default_account_id)
        @default_account_id
      else
        # Fall back to first available account
        @available_accounts.first
      end
    end

    # Validate that an account is in the available accounts list.
    #
    # @param account_id [String] The account ID to validate
    # @raise [Ibkr::ApiError] if the account is not available
    def validate_account_available!(account_id)
      return if account_available?(account_id)

      raise Ibkr::ApiError.account_not_found(
        account_id,
        context: {
          available_accounts: @available_accounts,
          operation: "set_active_account"
        }
      )
    end

    # Ensure the OAuth client is authenticated.
    #
    # @raise [Ibkr::AuthenticationError] if not authenticated
    def ensure_authenticated!
      return if @oauth_client.authenticated?

      raise Ibkr::AuthenticationError.credentials_invalid(
        "Client must be authenticated before account operations",
        context: {
          operation: "account_management",
          default_account_id: @default_account_id
        }
      )
    end
  end
end
