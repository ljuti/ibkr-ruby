# frozen_string_literal: true

require_relative "base"

module Ibkr
  module Models
    class Transaction < Base
      attribute :date, Ibkr::Types::String
      attribute :cur, Ibkr::Types::String # Currency
      attribute :pr, Ibkr::Types::IbkrNumber # Price
      attribute :qty, Ibkr::Types::IbkrNumber # Quantity
      attribute :amt, Ibkr::Types::IbkrNumber # Amount
      attribute :conid, Ibkr::Types::Integer # Contract ID
      attribute :desc, Ibkr::Types::String # Description
      attribute :type, Ibkr::Types::String # Transaction type

      # Convenience accessors with better names
      alias_method :currency, :cur
      alias_method :price, :pr
      alias_method :quantity, :qty
      alias_method :amount, :amt
      alias_method :contract_id, :conid
      alias_method :description, :desc
      alias_method :transaction_type, :type

      # Parse transaction date
      def transaction_date
        @transaction_date ||= Date.parse(date)
      rescue ArgumentError
        nil
      end

      def transaction_time
        @transaction_time ||= Time.parse(date)
      rescue ArgumentError
        nil
      end

      # Transaction type helpers
      def buy?
        transaction_type&.upcase&.include?("BUY") || quantity > 0
      end

      def sell?
        transaction_type&.upcase&.include?("SELL") || quantity < 0
      end

      def dividend?
        transaction_type&.upcase&.include?("DIV")
      end

      def fee?
        transaction_type&.upcase&.include?("FEE") || 
        transaction_type&.upcase&.include?("COMMISSION")
      end

      def interest?
        transaction_type&.upcase&.include?("INT")
      end

      # Value calculations
      def gross_value
        return amount if price.nil? || quantity.nil?
        
        price * quantity.abs
      end

      def net_value
        amount
      end

      # Display helpers
      def formatted_quantity
        if quantity == quantity.to_i
          quantity.to_i.to_s
        else
          quantity.to_s
        end
      end

      def formatted_amount(precision: 2)
        sprintf("%.#{precision}f", amount)
      end

      def side
        if buy?
          "BUY"
        elsif sell?
          "SELL"
        else
          transaction_type&.upcase || "OTHER"
        end
      end

      # Summary for reporting
      def summary_hash
        {
          date: date,
          symbol: description,
          side: side,
          quantity: formatted_quantity,
          price: price,
          amount: formatted_amount,
          currency: currency,
          type: transaction_type
        }.compact
      end

      # Check if transaction is recent
      def recent?(days = 30)
        return false unless transaction_date
        
        transaction_date >= Date.today - days
      end

      # Check if transaction is significant (above threshold)
      def significant?(threshold = 1000.0)
        amount.abs >= threshold
      end

      # Group transactions by type for analysis
      def self.group_by_type(transactions)
        transactions.group_by(&:transaction_type)
      end

      # Calculate total value for array of transactions
      def self.total_value(transactions)
        transactions.sum(&:amount)
      end

      # Filter transactions by date range
      def self.in_date_range(transactions, start_date, end_date)
        transactions.select do |txn|
          txn_date = txn.transaction_date
          txn_date && txn_date >= start_date && txn_date <= end_date
        end
      end
    end
  end
end