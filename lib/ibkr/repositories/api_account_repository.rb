# frozen_string_literal: true

require_relative "base_repository"
require_relative "account_repository_interface"

module Ibkr
  module Repositories
    # API-based implementation of AccountRepository
    # Makes direct calls to IBKR API endpoints
    class ApiAccountRepository < BaseRepository
      include AccountRepositoryInterface

      def find_summary(account_id)
        with_error_handling do
          ensure_authenticated!
          response = client.get("/v1/api/portfolio/#{account_id}/summary")
          normalize_and_create_summary(response, account_id)
        end
      end

      def find_metadata(account_id)
        with_error_handling do
          ensure_authenticated!
          client.get("/v1/api/portfolio/#{account_id}/meta")
        end
      end

      def find_positions(account_id, options = {})
        with_error_handling do
          ensure_authenticated!

          # Set defaults and normalize options
          normalized_options = {
            pageId: options[:page] || 0,
            sort: options[:sort] || "description",
            direction: options[:direction] || "asc"
          }

          client.get(
            "/v1/api/portfolio2/#{account_id}/positions",
            params: normalized_options
          )
        end
      end

      def find_transactions(account_id, contract_id, days = 90)
        with_error_handling do
          ensure_authenticated!

          body = {
            "acctIds" => [account_id],
            "conids" => [contract_id],
            "days" => days,
            "currency" => "USD"
          }

          client.post("/v1/api/pa/transactions", body: body)
        end
      end

      def discover_accounts
        with_error_handling do
          ensure_authenticated!

          # Initialize brokerage session if needed
          client.initialize_session(priority: true)

          # Fetch available accounts from IBKR API
          response = client.get("/v1/api/iserver/accounts")

          # Extract account IDs from the response
          response["accounts"] || []
        end
      end

      def account_exists?(account_id)
        with_error_handling do
          available_accounts = discover_accounts
          available_accounts.include?(account_id)
        end
      end

      private

      # Normalize IBKR API response and create Summary object
      def normalize_and_create_summary(raw_data, account_id)
        # Transform IBKR API keys to normalized attribute names
        normalized_data = normalize_summary_keys(raw_data)

        # Convert timestamps from milliseconds to Time objects
        normalized_data = convert_timestamps(normalized_data)

        # Add account ID to the data
        normalized_data["account_id"] = account_id

        # Create Summary object
        Ibkr::Accounts::Summary.new(normalized_data)
      end

      # Map IBKR API response keys to Summary model attributes
      def normalize_summary_keys(data)
        key_mapping = {
          "netliquidation" => "net_liquidation_value",
          "availablefunds" => "available_funds",
          "buyingpower" => "buying_power",
          "accruedcash" => "accrued_cash",
          "cushion" => "cushion",
          "equitywithloanvalue" => "equity_with_loan",
          "excessliquidity" => "excess_liquidity",
          "grosspositionvalue" => "gross_position_value",
          "initmarginreq" => "initial_margin",
          "maintmarginreq" => "maintenance_margin",
          "totalcashvalue" => "total_cash_value"
        }

        normalized = {}

        data.each do |key, value|
          normalized_key = key_mapping[key] || key
          normalized[normalized_key] = value
        end

        normalized
      end

      # Convert millisecond timestamps to Time objects
      def convert_timestamps(data)
        data.each do |key, value|
          next unless value.is_a?(Hash)

          if value["timestamp"].is_a?(Integer)
            # Convert from milliseconds to seconds
            value["timestamp"] = Time.at(value["timestamp"] / 1000.0)
          end
        end

        data
      end
    end
  end
end
