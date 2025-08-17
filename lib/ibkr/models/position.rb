# frozen_string_literal: true

require_relative "base"

module Ibkr
  module Models
    class Position < Base
      attribute :conid, Ibkr::Types::String
      attribute :position, Ibkr::Types::PositionSize
      attribute? :average_cost, Ibkr::Types::IbkrNumber.optional
      attribute? :average_price, Ibkr::Types::IbkrNumber.optional
      attribute :currency, Ibkr::Types::String
      attribute :description, Ibkr::Types::String
      attribute :unrealized_pnl, Ibkr::Types::IbkrNumber
      attribute :realized_pnl, Ibkr::Types::IbkrNumber
      attribute :market_value, Ibkr::Types::IbkrNumber
      attribute :market_price, Ibkr::Types::IbkrNumber
      attribute :security_type, Ibkr::Types::String
      attribute :asset_class, Ibkr::Types::String
      attribute :sector, Ibkr::Types::String
      attribute :group, Ibkr::Types::String

      # Position type helpers
      def long?
        position > 0
      end

      def short?
        position < 0
      end

      def flat?
        position == 0
      end

      # P&L calculations
      def total_pnl
        return nil unless unrealized_pnl && realized_pnl

        unrealized_pnl + realized_pnl
      end

      def pnl_percentage
        return nil unless unrealized_pnl && average_cost && position != 0

        cost_basis = (average_cost * position.abs)
        return nil if cost_basis == 0

        (unrealized_pnl / cost_basis * 100).round(2)
      end

      # Position value calculations
      def notional_value
        return nil unless market_price

        market_price * position.abs
      end

      def cost_basis
        return nil unless average_cost

        average_cost * position.abs
      end

      # Risk metrics
      def exposure_percentage(account_net_liquidation)
        return nil unless market_value && account_net_liquidation && account_net_liquidation > 0

        (market_value.abs / account_net_liquidation * 100).round(2)
      end

      # Display helpers
      def formatted_position
        if position == position.to_i
          position.to_i.to_s
        else
          position.to_s
        end
      end

      def position_summary
        direction = if long?
          "LONG"
        else
          (short? ? "SHORT" : "FLAT")
        end
        "#{direction} #{formatted_position} #{description}"
      end

      # Check if position needs attention (large unrealized loss)
      def attention_needed?(threshold_percentage = -10.0)
        return false unless pnl_percentage

        pnl_percentage <= threshold_percentage
      end

      # Convert to simple hash for reporting
      def summary_hash
        {
          symbol: description,
          position: formatted_position,
          market_value: market_value,
          unrealized_pnl: unrealized_pnl,
          pnl_percentage: pnl_percentage,
          direction: if long?
                       "LONG"
                     else
                       (short? ? "SHORT" : "FLAT")
                     end
        }.compact
      end
    end
  end
end
