# frozen_string_literal: true

require "dry-struct"
require_relative "../types"
require_relative "base"

module Ibkr
  module Models
    class FlexReport < Base
      attribute :reference_code, Types::Strict::String
      attribute :report_type, Types::Strict::String
      attribute :generated_at, Types::TimeFromUnix
      attribute? :account_id, Types::Strict::String.optional
      attribute? :from_date, Types::Strict::Date.optional
      attribute? :to_date, Types::Strict::Date.optional
      attribute? :status, Types::Strict::String.optional.default("ready")
      attribute? :data, Types::Strict::Hash.optional.default({}.freeze)

      def ready?
        status == "ready"
      end

      def processing?
        status == "processing"
      end

      def expired?
        status == "expired"
      end

      def has_data?
        !data.empty?
      end

      def trades
        return [] unless data[:transactions]
        data[:transactions].is_a?(Array) ? data[:transactions] : [data[:transactions]]
      end

      def positions
        return [] unless data[:positions]
        data[:positions].is_a?(Array) ? data[:positions] : [data[:positions]]
      end

      def cash_reports
        return [] unless data[:cash_report]
        data[:cash_report].is_a?(Array) ? data[:cash_report] : [data[:cash_report]]
      end

      def query_name
        data[:query_name]
      end

      def period
        data[:period]
      end

      def account_alias
        data[:account_alias]
      end

      def account_model
        data[:account_model]
      end

      def account_currency
        data[:account_currency]
      end
    end

    class FlexTransaction < Base
      attribute :transaction_id, Types::Strict::String
      attribute :account_id, Types::Strict::String
      attribute :symbol, Types::Strict::String
      attribute :trade_date, Types::Strict::Date
      attribute :settle_date, Types::Strict::Date
      attribute :quantity, Types::Coercible::Float
      attribute :price, Types::Coercible::Float
      attribute :proceeds, Types::Coercible::Float
      attribute :commission, Types::Coercible::Float
      attribute :currency, Types::Strict::String
      attribute :asset_class, Types::Strict::String
      attribute? :description, Types::Strict::String.optional
      attribute? :order_time, Types::Strict::DateTime.optional
      attribute? :exchange, Types::Strict::String.optional
      attribute? :put_call, Types::Strict::String.optional
      attribute? :strike, Types::Coercible::Float.optional
      attribute? :expiry, Types::Strict::Date.optional

      def option?
        asset_class == "OPT"
      end

      def stock?
        asset_class == "STK"
      end

      def forex?
        asset_class == "CASH"
      end

      def net_amount
        proceeds - commission.abs
      end
    end

    class FlexPosition < Base
      attribute :account_id, Types::Strict::String
      attribute :symbol, Types::Strict::String
      attribute :position, Types::Coercible::Float
      attribute :market_price, Types::Coercible::Float
      attribute :market_value, Types::Coercible::Float
      attribute :average_cost, Types::Coercible::Float
      attribute :unrealized_pnl, Types::Coercible::Float
      attribute :realized_pnl, Types::Coercible::Float
      attribute :currency, Types::Strict::String
      attribute :asset_class, Types::Strict::String
      attribute? :contract_id, Types::Strict::String.optional
      attribute? :multiplier, Types::Coercible::Integer.optional.default(1)
      attribute? :cost_basis, Types::Coercible::Float.optional
      attribute? :percent_of_nav, Types::Coercible::Float.optional

      def long?
        position.positive?
      end

      def short?
        position.negative?
      end

      def total_pnl
        unrealized_pnl + realized_pnl
      end

      def pnl_percentage
        return 0 if average_cost.zero?
        (unrealized_pnl / (average_cost * position.abs) * 100).round(2)
      end
    end

    class FlexCashReport < Base
      attribute :account_id, Types::Strict::String
      attribute :currency, Types::Strict::String
      attribute :starting_cash, Types::Coercible::Float
      attribute :ending_cash, Types::Coercible::Float
      attribute :deposits, Types::Coercible::Float
      attribute :withdrawals, Types::Coercible::Float
      attribute :fees, Types::Coercible::Float
      attribute :dividends, Types::Coercible::Float
      attribute :interest, Types::Coercible::Float
      attribute :realized_pnl, Types::Coercible::Float
      attribute? :forex_pnl, Types::Coercible::Float.optional.default(0)
      attribute? :other, Types::Coercible::Float.optional.default(0)

      def net_change
        ending_cash - starting_cash
      end

      def trading_pnl
        realized_pnl + forex_pnl
      end

      def total_income
        dividends + interest
      end

      def total_fees
        fees.abs
      end
    end

    class FlexPerformance < Base
      attribute :account_id, Types::Strict::String
      attribute :period, Types::Strict::String
      attribute :nav_start, Types::Coercible::Float
      attribute :nav_end, Types::Coercible::Float
      attribute :deposits, Types::Coercible::Float
      attribute :withdrawals, Types::Coercible::Float
      attribute :realized_pnl, Types::Coercible::Float
      attribute :unrealized_pnl, Types::Coercible::Float
      attribute :dividends, Types::Coercible::Float
      attribute :interest, Types::Coercible::Float
      attribute :commissions, Types::Coercible::Float
      attribute? :twr, Types::Coercible::Float.optional
      attribute? :mwr, Types::Coercible::Float.optional

      def total_pnl
        realized_pnl + unrealized_pnl
      end

      def net_performance
        nav_end - nav_start - deposits + withdrawals
      end

      def return_percentage
        return 0 if nav_start.zero?
        (net_performance / nav_start * 100).round(2)
      end
    end

    class FlexStatementResponse < Base
      attribute :reference_code, Types::Strict::String
      attribute :url, Types::Strict::String
      attribute :status, Types::Strict::String

      def success?
        status == "Success"
      end

      def ready?
        status == "Ready"
      end

      def processing?
        ["InProgress", "Queued"].include?(status)
      end

      def failed?
        ["Failed", "Error"].include?(status)
      end
    end
  end
end