# frozen_string_literal: true

require_relative "base"
require_relative "../models/account_summary"
require_relative "../models/position"
require_relative "../models/transaction"
require_relative "../repositories/repository_factory"

module Ibkr
  module Services
    class Accounts < Base
      def initialize(client, repository: nil)
        super(client)
        @repository = repository || Repositories::RepositoryFactory.create_auto_repository(client)
      end

      # Expose the current account ID for compatibility
      def account_id
        client.account_id
      end

      # Get account metadata
      def get
        @repository.find_metadata(account_id)
      end

      # Get account summary with all balance information
      def summary
        @repository.find_summary(account_id)
      end

      # Get account positions with pagination and sorting
      def positions(page: 0, sort: "description", direction: "asc")
        @repository.find_positions(account_id, page: page, sort: sort, direction: direction)
      end

      # Get transaction history for a specific contract
      def transactions(contract_id, days = 90, currency: "USD")
        @repository.find_transactions(account_id, contract_id, days)
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
