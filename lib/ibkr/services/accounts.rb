# frozen_string_literal: true

require_relative "base"
require_relative "../models/account_summary"
require_relative "../models/position"
require_relative "../models/transaction"

module Ibkr
  module Services
    class Accounts < Base
      # Get account metadata
      def get
        ensure_authenticated!
        client.oauth_client.get(account_path("/meta"))
      end

      # Get account summary with all balance information
      def summary
        ensure_authenticated!
        
        response = client.oauth_client.get(account_path("/summary"))
        normalized_data = normalize_summary(response)
        
        Models::AccountSummary.new(normalized_data.merge("account_id" => account_id))
      end

      # Get account positions with pagination and sorting
      def positions(page: 0, sort: "description", direction: "asc")
        ensure_authenticated!
        
        params = {
          pageId: page,
          sort: sort,
          direction: direction
        }
        
        client.oauth_client.get("/v1/api/portfolio2/#{account_id}/positions", params: params)
      end

      # Get transaction history for a specific contract
      def transactions(contract_id, days = 90, currency: "USD")
        ensure_authenticated!
        
        body = {
          "acctIds" => [account_id],
          "conids" => [contract_id],
          "days" => days,
          "currency" => currency
        }
        
        client.oauth_client.post(api_path("/pa/transactions"), body: body)
      end

      # Get all account positions (convenience method)
      def all_positions
        positions = []
        page = 0
        
        loop do
          page_positions = positions(page: page)
          break if page_positions.empty?
          
          positions.concat(page_positions)
          page += 1
          
          # Safety break to avoid infinite loops
          break if page > 100
        end
        
        positions
      end

      private

      # Normalize summary data from IBKR format to our model format
      def normalize_summary(data)
        return {} unless data.is_a?(Hash)

        # Transform keys using the mapping from the original prototype
        key_mapping = Models::AccountSummary::KEY_MAPPING
        transformed = data.transform_keys { |key| key_mapping[key] || key }
        
        # Transform timestamp values from milliseconds to Time objects
        transformed.transform_values do |value|
          if value.is_a?(Hash) && value["timestamp"]
            value.merge("timestamp" => Ibkr::Types::TimeFromUnix[value["timestamp"]])
          else
            value
          end
        end
      end
    end
  end
end