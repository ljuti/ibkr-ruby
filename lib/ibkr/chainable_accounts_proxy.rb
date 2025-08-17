# frozen_string_literal: true

module Ibkr
  # Chainable proxy for account operations that provides a fluent interface
  class ChainableAccountsProxy
    attr_reader :page, :sort_field, :sort_direction, :period_days, :contract_id

    def initialize(client)
      @client = client
      @accounts_service = nil
    end

    # Lazy load the accounts service
    def accounts_service
      @accounts_service ||= @client.accounts
    end

    # Fluent methods that return results directly

    def summary
      accounts_service.summary
    end

    def positions(page: 0, sort: "description", direction: "asc")
      accounts_service.positions(page: page, sort: sort, direction: direction)
    end

    def transactions(contract_id, days = 90)
      accounts_service.transactions(contract_id, days)
    end

    def metadata
      accounts_service.get
    end

    # Chainable methods that return self for further chaining

    def with_page(page_num)
      @page = page_num
      self
    end

    def sorted_by(field, direction = "asc")
      @sort_field = field
      @sort_direction = direction
      self
    end

    def for_period(days)
      @period_days = days
      self
    end

    def for_contract(contract_id)
      @contract_id = contract_id
      self
    end

    # Terminal methods that execute with accumulated options

    def positions_with_options
      accounts_service.positions(
        page: @page || 0,
        sort: @sort_field || "description",
        direction: @sort_direction || "asc"
      )
    end

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
