# frozen_string_literal: true

# Compatibility layer for tests - delegates to Services::Accounts
require_relative "services/accounts"
require_relative "models/account_summary"
require_relative "models/position"
require_relative "models/transaction"

module Ibkr
  # Backward compatibility class that delegates to Services::Accounts
  class Accounts < Services::Accounts
    # Re-export models under Accounts namespace for test compatibility
    Summary = Models::AccountSummary
    AccountValue = Models::AccountValue
    Position = Models::Position
    Transaction = Models::Transaction

    def initialize(client)
      super
      # Use the expected instance variable name for tests
      @_client = @client
    end

    # Make account_id public for tests
    def account_id
      super
    end
  end
end
