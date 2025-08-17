# frozen_string_literal: true

require_relative "base"

module Ibkr
  module Models
    class AccountValue < Base
      attribute? :value, Ibkr::Types::IbkrNumber.optional.default(nil)
      attribute? :currency, Ibkr::Types::StringOrNil.default(nil)
      attribute? :amount, Ibkr::Types::IbkrNumber.optional.default(nil)
      attribute? :timestamp, Ibkr::Types::TimeFromUnix.optional.default(nil)
    end

    class AccountSummary < Base
      # Mapping from IBKR API keys to our normalized names
      KEY_MAPPING = {
        "accruedcash" => "accrued_cash",
        "availablefunds" => "available_funds",
        "buyingpower" => "buying_power",
        "cushion" => "cushion",
        "equitywithloanvalue" => "equity_with_loan",
        "excessliquidity" => "excess_liquidity",
        "grosspositionvalue" => "gross_position_value",
        "initmarginreq" => "initial_margin",
        "maintmarginreq" => "maintenance_margin",
        "netliquidation" => "net_liquidation_value",
        "totalcashvalue" => "total_cash_value"
      }.freeze

      attribute :account_id, Ibkr::Types::String

      # Account balance components
      attribute? :accrued_cash, AccountValue.optional.default(nil)
      attribute? :available_funds, AccountValue.optional.default(nil)
      attribute? :buying_power, AccountValue.optional.default(nil)
      attribute? :cushion, AccountValue.optional.default(nil)
      attribute? :equity_with_loan, AccountValue.optional.default(nil)
      attribute? :excess_liquidity, AccountValue.optional.default(nil)
      attribute? :gross_position_value, AccountValue.optional.default(nil)
      attribute? :initial_margin, AccountValue.optional.default(nil)
      attribute? :maintenance_margin, AccountValue.optional.default(nil)
      attribute :net_liquidation_value, AccountValue
      attribute? :total_cash_value, AccountValue.optional.default(nil)

      # Convenience methods for common values
      def net_liquidation
        net_liquidation_value&.value
      end

      def available_cash
        available_funds&.value
      end

      def buying_power_amount
        buying_power&.value
      end

      def total_cash
        total_cash_value&.value
      end

      # Get all balance components as a hash
      def balances
        {
          net_liquidation: net_liquidation,
          available_cash: available_cash,
          buying_power: buying_power_amount,
          total_cash: total_cash,
          equity_with_loan: equity_with_loan&.value,
          gross_position_value: gross_position_value&.value
        }.compact
      end

      # Check if account has sufficient buying power
      def sufficient_buying_power?(amount)
        return false unless buying_power_amount

        buying_power_amount >= amount
      end

      # Calculate account utilization as percentage
      def utilization_percentage
        return 0.0 unless net_liquidation && net_liquidation > 0
        return 0.0 unless initial_margin&.value

        (initial_margin.value / net_liquidation * 100).round(2)
      end
    end
  end
end
