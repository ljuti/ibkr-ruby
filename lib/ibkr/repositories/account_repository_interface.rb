# frozen_string_literal: true

module Ibkr
  module Repositories
    # Interface defining the contract for account data access
    # All account repository implementations must implement these methods
    module AccountRepositoryInterface
      # Retrieve account summary data
      # @param account_id [String] The account ID
      # @return [Ibkr::Accounts::Summary] Account summary object
      def find_summary(account_id)
        raise NotImplementedError, "Subclasses must implement #find_summary"
      end

      # Retrieve account metadata
      # @param account_id [String] The account ID
      # @return [Hash] Account metadata
      def find_metadata(account_id)
        raise NotImplementedError, "Subclasses must implement #find_metadata"
      end

      # Retrieve account positions
      # @param account_id [String] The account ID
      # @param options [Hash] Query options (page, sort, direction)
      # @return [Hash] Positions data with results array
      def find_positions(account_id, options = {})
        raise NotImplementedError, "Subclasses must implement #find_positions"
      end

      # Retrieve transaction history
      # @param account_id [String] The account ID
      # @param contract_id [Integer] Contract identifier
      # @param days [Integer] Number of days to look back
      # @return [Array<Hash>] Transaction records
      def find_transactions(account_id, contract_id, days = 90)
        raise NotImplementedError, "Subclasses must implement #find_transactions"
      end

      # Discover available accounts for the current credentials
      # @return [Array<String>] List of available account IDs
      def discover_accounts
        raise NotImplementedError, "Subclasses must implement #discover_accounts"
      end

      # Check if account exists and is accessible
      # @param account_id [String] The account ID
      # @return [Boolean] True if account is accessible
      def account_exists?(account_id)
        raise NotImplementedError, "Subclasses must implement #account_exists?"
      end
    end
  end
end
