# frozen_string_literal: true

module Ibkr
  # Chainable proxy for account operations that provides a fluent interface
  #
  # This class provides a fluent, chainable API for portfolio operations,
  # allowing for more readable and expressive code when working with account data.
  #
  # @example Basic usage
  #   client.portfolio.summary
  #   client.portfolio.positions
  #
  # @example Chained operations
  #   client.portfolio
  #     .with_page(2)
  #     .sorted_by("market_value", "desc")
  #     .positions_with_options
  class ChainableAccountsProxy
    attr_reader :page, :sort_field, :sort_direction, :period_days, :contract_id

    # @param client [Ibkr::Client] The client instance to proxy for
    def initialize(client)
      @client = client
      @accounts_service = nil
    end

    # Lazy load the accounts service
    # @return [Ibkr::Accounts] The accounts service instance
    def accounts_service
      @accounts_service ||= @client.accounts
    end

    # Fluent methods that return results directly

    # Get account summary with balance information
    # @return [Ibkr::Models::AccountSummary] Account summary data
    # @example
    #   summary = client.portfolio.summary
    #   puts summary.net_liquidation_value.amount
    def summary
      accounts_service.summary
    end

    # Get portfolio positions with optional parameters
    # @param page [Integer] Page number for pagination (default: 0)
    # @param sort [String] Field to sort by (default: "description")
    # @param direction [String] Sort direction - "asc" or "desc" (default: "asc")
    # @return [Hash] Positions data with results array
    # @example
    #   positions = client.portfolio.positions(page: 1, sort: "market_value")
    def positions(page: 0, sort: "description", direction: "asc")
      accounts_service.positions(page: page, sort: sort, direction: direction)
    end

    # Get transaction history for a contract
    # @param contract_id [Integer] Contract ID to get transactions for
    # @param days [Integer] Number of days of history (default: 90)
    # @return [Array<Hash>] Transaction records
    # @example
    #   transactions = client.portfolio.transactions(265598, 30)
    def transactions(contract_id, days = 90)
      accounts_service.transactions(contract_id, days)
    end

    # Get raw account metadata
    # @return [Hash] Account metadata
    def metadata
      accounts_service.get
    end

    # Chainable methods that return self for further chaining

    # Set the page number for pagination
    # @param page_num [Integer] Page number
    # @return [self] Returns self for chaining
    # @example
    #   client.portfolio.with_page(2).positions_with_options
    def with_page(page_num)
      @page = page_num
      self
    end

    # Set sorting parameters
    # @param field [String] Field to sort by
    # @param direction [String] Sort direction - "asc" or "desc"
    # @return [self] Returns self for chaining
    # @example
    #   client.portfolio.sorted_by("unrealized_pnl", "desc").positions_with_options
    def sorted_by(field, direction = "asc")
      @sort_field = field
      @sort_direction = direction
      self
    end

    # Set the time period for transaction queries
    # @param days [Integer] Number of days of history
    # @return [self] Returns self for chaining
    # @example
    #   client.portfolio.for_period(30).for_contract(265598).transactions_with_options
    def for_period(days)
      @period_days = days
      self
    end

    # Set the contract ID for transaction queries
    # @param contract_id [Integer] Contract ID
    # @return [self] Returns self for chaining
    # @example
    #   client.portfolio.for_contract(265598).transactions_with_options
    def for_contract(contract_id)
      @contract_id = contract_id
      self
    end

    # Terminal methods that execute with accumulated options

    # Execute positions query with accumulated options
    # @return [Hash] Positions data with results array
    # @example
    #   positions = client.portfolio
    #     .with_page(1)
    #     .sorted_by("market_value", "desc")
    #     .positions_with_options
    def positions_with_options
      accounts_service.positions(
        page: @page || 0,
        sort: @sort_field || "description",
        direction: @sort_direction || "asc"
      )
    end

    # Execute transactions query with accumulated options
    # @return [Array<Hash>] Transaction records
    # @raise [ArgumentError] if contract ID not specified
    # @example
    #   transactions = client.portfolio
    #     .for_contract(265598)
    #     .for_period(60)
    #     .transactions_with_options
    def transactions_with_options
      unless @contract_id
        raise ArgumentError, "Contract ID must be specified with for_contract(id)"
      end

      accounts_service.transactions(@contract_id, @period_days || 90)
    end

    # Delegate methods for compatibility
    def method_missing(method_name, *args, &block)
      if accounts_service.respond_to?(method_name)
        accounts_service.send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      accounts_service.respond_to?(method_name, include_private) || super
    end
  end
end
