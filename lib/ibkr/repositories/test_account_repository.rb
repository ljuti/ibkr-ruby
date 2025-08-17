# frozen_string_literal: true

require "date"
require_relative "base_repository"
require_relative "account_repository_interface"

module Ibkr
  module Repositories
    # Test implementation of AccountRepository
    # Returns predefined test data without making API calls
    class TestAccountRepository < BaseRepository
      include AccountRepositoryInterface

      def initialize(client, test_data: nil)
        super(client)
        @test_data = test_data || default_test_data
      end

      def find_summary(account_id)
        validate_test_account!(account_id)

        summary_data = @test_data[:summaries][account_id] || @test_data[:summaries][:default]
        Ibkr::Accounts::Summary.new(summary_data.merge(account_id: account_id))
      end

      def find_metadata(account_id)
        validate_test_account!(account_id)

        @test_data[:metadata][account_id] || @test_data[:metadata][:default]
      end

      def find_positions(account_id, options = {})
        validate_test_account!(account_id)

        positions = @test_data[:positions][account_id] || @test_data[:positions][:default]

        # Apply pagination and sorting if specified
        results = positions["results"] || []

        if options[:sort] && options[:sort] != "description"
          # Simple sorting simulation
          results = results.sort_by { |pos| pos[options[:sort]] || 0 }
          results.reverse! if options[:direction] == "desc"
        end

        if options[:page] && options[:page] > 0
          # Simple pagination simulation
          page_size = 20
          start_index = options[:page] * page_size
          results = results[start_index, page_size] || []
        end

        {"results" => results}
      end

      def find_transactions(account_id, contract_id, days = 90)
        validate_test_account!(account_id)

        all_transactions = @test_data[:transactions][account_id] || @test_data[:transactions][:default] || []

        # Filter by contract ID and days
        all_transactions.select do |transaction|
          transaction["conid"] == contract_id &&
            transaction_within_days?(transaction, days)
        end
      end

      def discover_accounts
        @test_data[:available_accounts]
      end

      def account_exists?(account_id)
        discover_accounts.include?(account_id)
      end

      # Test helper methods

      def set_test_data(data)
        @test_data = data
      end

      def add_test_account(account_id, data = {})
        @test_data[:available_accounts] << account_id unless @test_data[:available_accounts].include?(account_id)
        @test_data[:summaries][account_id] = data[:summary] if data[:summary]
        @test_data[:metadata][account_id] = data[:metadata] if data[:metadata]
        @test_data[:positions][account_id] = data[:positions] if data[:positions]
        @test_data[:transactions][account_id] = data[:transactions] if data[:transactions]
      end

      def simulate_api_error(error_class = Ibkr::ApiError, message = "Simulated API error")
        @api_error = {class: error_class, message: message}
      end

      def clear_api_error
        @api_error = nil
      end

      private

      def validate_test_account!(account_id)
        if @api_error
          raise @api_error[:class], @api_error[:message]
        end

        unless account_exists?(account_id)
          raise Ibkr::ApiError, "Account #{account_id} not found in test data"
        end
      end

      def transaction_within_days?(transaction, days)
        return true unless transaction["date"]

        transaction_date = Date.parse(transaction["date"])
        cutoff_date = Date.today - days
        transaction_date >= cutoff_date
      rescue Date::Error
        true # If date parsing fails, include the transaction
      end

      def default_test_data
        {
          available_accounts: ["DU123456", "DU789012"],
          summaries: {
            default: {
              net_liquidation_value: {amount: 50000.0, currency: "USD", timestamp: Time.now},
              available_funds: {amount: 25000.0, currency: "USD", timestamp: Time.now},
              buying_power: {amount: 100000.0, currency: "USD", timestamp: Time.now},
              accrued_cash: {amount: 45.67, currency: "USD", timestamp: Time.now},
              cushion: {value: 0.85},
              equity_with_loan: {amount: 50000.0, currency: "USD", timestamp: Time.now},
              excess_liquidity: {amount: 30000.0, currency: "USD", timestamp: Time.now},
              gross_position_value: {amount: 75000.0, currency: "USD", timestamp: Time.now},
              initial_margin: {amount: 15000.0, currency: "USD", timestamp: Time.now},
              maintenance_margin: {amount: 12000.0, currency: "USD", timestamp: Time.now},
              total_cash_value: {amount: 25000.0, currency: "USD", timestamp: Time.now}
            }
          },
          metadata: {
            default: {
              "id" => "DU123456",
              "accountType" => "DEMO",
              "accountTitle" => "Test Account",
              "displayName" => "DU123456",
              "currency" => "USD",
              "type" => "DEMO"
            }
          },
          positions: {
            default: {
              "results" => [
                {
                  "conid" => "265598",
                  "position" => 100,
                  "average_cost" => 150.25,
                  "currency" => "USD",
                  "description" => "APPLE INC",
                  "unrealized_pnl" => 1250.50,
                  "market_value" => 16275.00,
                  "market_price" => 162.75
                },
                {
                  "conid" => "76792991",
                  "position" => 50,
                  "average_cost" => 95.50,
                  "currency" => "USD",
                  "description" => "MICROSOFT CORP",
                  "unrealized_pnl" => 525.00,
                  "market_value" => 5300.00,
                  "market_price" => 106.00
                }
              ]
            }
          },
          transactions: {
            default: [
              {
                "date" => (Date.today - 5).to_s,
                "cur" => "USD",
                "pr" => 150.25,
                "qty" => 100,
                "amt" => -15025.00,
                "conid" => 265598,
                "desc" => "AAPL BUY",
                "type" => "Trades"
              },
              {
                "date" => (Date.today - 10).to_s,
                "cur" => "USD",
                "pr" => 148.75,
                "qty" => -50,
                "amt" => 7437.50,
                "conid" => 265598,
                "desc" => "AAPL SELL",
                "type" => "Trades"
              }
            ]
          }
        }
      end
    end
  end
end
