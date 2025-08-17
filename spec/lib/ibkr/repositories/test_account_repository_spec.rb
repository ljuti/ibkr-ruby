# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Repositories::TestAccountRepository do
  let(:client) { double("client") }
  let(:custom_test_data) do
    {
      available_accounts: ["TEST001", "TEST002"],
      summaries: {
        "TEST001" => {
          net_liquidation_value: {amount: 100000.0, currency: "USD", timestamp: Time.now}
        }
      },
      metadata: {
        "TEST001" => {"id" => "TEST001", "accountType" => "TEST"}
      },
      positions: {
        "TEST001" => {"results" => [{"conid" => "123", "position" => 100}]}
      },
      transactions: {
        "TEST001" => [{"date" => "2024-08-15", "conid" => 123, "qty" => 50}]
      }
    }
  end

  describe "initialization" do
    context "with default test data" do
      subject(:repository) { described_class.new(client) }

      it "inherits from BaseRepository" do
        expect(repository).to be_a(Ibkr::Repositories::BaseRepository)
      end

      it "includes AccountRepositoryInterface" do
        expect(repository).to be_a(Ibkr::Repositories::AccountRepositoryInterface)
      end

      it "initializes with default test accounts" do
        expect(repository.discover_accounts).to eq(["DU123456", "DU789012"])
      end

      it "provides access to client through parent class" do
        expect(repository.send(:client)).to eq(client)
      end
    end

    context "with custom test data" do
      subject(:repository) { described_class.new(client, test_data: custom_test_data) }

      it "uses provided test data" do
        expect(repository.discover_accounts).to eq(["TEST001", "TEST002"])
      end
    end
  end

  describe "account discovery" do
    subject(:repository) { described_class.new(client) }

    describe "#discover_accounts" do
      it "returns array of available test account IDs" do
        accounts = repository.discover_accounts
        expect(accounts).to be_an(Array)
        expect(accounts).to include("DU123456", "DU789012")
      end
    end

    describe "#account_exists?" do
      context "when account exists in test data" do
        it "returns true" do
          expect(repository.account_exists?("DU123456")).to be true
        end
      end

      context "when account does not exist in test data" do
        it "returns false" do
          expect(repository.account_exists?("NONEXISTENT")).to be false
        end
      end
    end
  end

  describe "account summary retrieval" do
    subject(:repository) { described_class.new(client) }

    describe "#find_summary" do
      context "with valid account ID" do
        it "returns account summary object" do
          summary = repository.find_summary("DU123456")

          expect(summary).to be_a(Ibkr::Accounts::Summary)
          expect(summary.account_id).to eq("DU123456")
        end

        it "includes default summary data" do
          summary = repository.find_summary("DU123456")

          expect(summary.net_liquidation_value[:amount]).to eq(50000.0)
          expect(summary.available_funds[:amount]).to eq(25000.0)
          expect(summary.buying_power[:amount]).to eq(100000.0)
        end
      end

      context "with account not in test data" do
        it "raises API error" do
          expect { repository.find_summary("INVALID") }.to raise_error(
            Ibkr::ApiError,
            "Account INVALID not found in test data"
          )
        end
      end

      context "with custom account-specific data" do
        let(:repository) { described_class.new(client, test_data: custom_test_data) }

        it "returns account-specific summary data" do
          summary = repository.find_summary("TEST001")

          expect(summary.account_id).to eq("TEST001")
          expect(summary.net_liquidation_value[:amount]).to eq(100000.0)
        end
      end

      context "when API error is simulated" do
        before { repository.simulate_api_error(Ibkr::AuthenticationError, "Auth failed") }

        it "raises the simulated error" do
          expect { repository.find_summary("DU123456") }.to raise_error(
            Ibkr::AuthenticationError,
            "Auth failed"
          )
        end
      end
    end
  end

  describe "account metadata retrieval" do
    subject(:repository) { described_class.new(client) }

    describe "#find_metadata" do
      context "with valid account ID" do
        it "returns metadata hash" do
          metadata = repository.find_metadata("DU123456")

          expect(metadata).to be_a(Hash)
          expect(metadata["id"]).to eq("DU123456")
          expect(metadata["accountType"]).to eq("DEMO")
          expect(metadata["currency"]).to eq("USD")
        end
      end

      context "with account not in test data" do
        it "raises API error" do
          expect { repository.find_metadata("INVALID") }.to raise_error(
            Ibkr::ApiError,
            "Account INVALID not found in test data"
          )
        end
      end

      context "with custom metadata" do
        let(:repository) { described_class.new(client, test_data: custom_test_data) }

        it "returns custom metadata" do
          metadata = repository.find_metadata("TEST001")

          expect(metadata["id"]).to eq("TEST001")
          expect(metadata["accountType"]).to eq("TEST")
        end
      end
    end
  end

  describe "position retrieval" do
    subject(:repository) { described_class.new(client) }

    describe "#find_positions" do
      context "with valid account ID and no options" do
        it "returns positions data with results array" do
          positions = repository.find_positions("DU123456")

          expect(positions).to be_a(Hash)
          expect(positions["results"]).to be_an(Array)
          expect(positions["results"].length).to eq(2)
        end

        it "includes position details" do
          positions = repository.find_positions("DU123456")
          apple_position = positions["results"].first

          expect(apple_position["conid"]).to eq("265598")
          expect(apple_position["position"]).to eq(100)
          expect(apple_position["description"]).to eq("APPLE INC")
          expect(apple_position["unrealized_pnl"]).to eq(1250.50)
        end
      end

      context "with sorting options" do
        it "sorts results by specified field in ascending order" do
          positions = repository.find_positions("DU123456", sort: "position", direction: "asc")
          results = positions["results"]

          expect(results.first["position"]).to be <= results.last["position"]
        end

        it "sorts results by specified field in descending order" do
          positions = repository.find_positions("DU123456", sort: "position", direction: "desc")
          results = positions["results"]

          expect(results.first["position"]).to be >= results.last["position"]
        end

        it "ignores sorting for description field" do
          original_positions = repository.find_positions("DU123456")
          sorted_positions = repository.find_positions("DU123456", sort: "description")

          expect(sorted_positions["results"]).to eq(original_positions["results"])
        end
      end

      context "with pagination options" do
        let(:large_positions_data) do
          {
            available_accounts: ["DU123456"],
            positions: {
              "DU123456" => {
                "results" => (1..50).map do |i|
                  {"conid" => i.to_s, "position" => i, "description" => "Stock #{i}"}
                end
              }
            },
            summaries: {default: {}},
            metadata: {default: {}},
            transactions: {default: []}
          }
        end
        let(:repository) { described_class.new(client, test_data: large_positions_data) }

        it "returns all results when page is 0" do
          positions = repository.find_positions("DU123456", page: 0)
          results = positions["results"]

          expect(results.length).to eq(50)
          expect(results.first["conid"]).to eq("1")
          expect(results.last["conid"]).to eq("50")
        end

        it "returns first page when page is 1" do
          positions = repository.find_positions("DU123456", page: 1)
          results = positions["results"]

          expect(results.length).to eq(20)
          expect(results.first["conid"]).to eq("21")
          expect(results.last["conid"]).to eq("40")
        end

        it "returns second page when page is 2" do
          positions = repository.find_positions("DU123456", page: 2)
          results = positions["results"]

          expect(results.length).to eq(10)
          expect(results.first["conid"]).to eq("41")
          expect(results.last["conid"]).to eq("50")
        end

        it "returns empty array for page beyond available data" do
          positions = repository.find_positions("DU123456", page: 3)
          results = positions["results"]

          expect(results).to eq([])
        end
      end

      context "with account not in test data" do
        it "raises API error" do
          expect { repository.find_positions("INVALID") }.to raise_error(
            Ibkr::ApiError,
            "Account INVALID not found in test data"
          )
        end
      end
    end
  end

  describe "transaction retrieval" do
    subject(:repository) { described_class.new(client) }

    describe "#find_transactions" do
      context "with valid account and contract ID" do
        it "returns transactions for the specified contract" do
          transactions = repository.find_transactions("DU123456", 265598)

          expect(transactions).to be_an(Array)
          expect(transactions.length).to eq(2)

          transactions.each do |transaction|
            expect(transaction["conid"]).to eq(265598)
          end
        end

        it "includes transaction details" do
          transactions = repository.find_transactions("DU123456", 265598)
          buy_transaction = transactions.first

          expect(buy_transaction["date"]).to eq((Date.today - 5).to_s)
          expect(buy_transaction["qty"]).to eq(100)
          expect(buy_transaction["pr"]).to eq(150.25)
          expect(buy_transaction["desc"]).to eq("AAPL BUY")
        end
      end

      context "with date filtering" do
        let(:old_transaction_data) do
          {
            available_accounts: ["DU123456"],
            transactions: {
              "DU123456" => [
                {"date" => Date.today.to_s, "conid" => 265598, "desc" => "Recent"},
                {"date" => "2024-01-01", "conid" => 265598, "desc" => "Old"},
                {"date" => "invalid-date", "conid" => 265598, "desc" => "Invalid date"}
              ]
            },
            summaries: {default: {}},
            metadata: {default: {}},
            positions: {default: {"results" => []}}
          }
        end
        let(:repository) { described_class.new(client, test_data: old_transaction_data) }

        it "filters transactions by number of days" do
          recent_transactions = repository.find_transactions("DU123456", 265598, 30)

          # Should include recent and invalid-date transactions (invalid dates are included)
          expect(recent_transactions.length).to eq(2)
          expect(recent_transactions.map { |t| t["desc"] }).to include("Recent", "Invalid date")
        end

        it "includes transactions with invalid dates" do
          all_transactions = repository.find_transactions("DU123456", 265598, 365)

          invalid_date_transaction = all_transactions.find { |t| t["desc"] == "Invalid date" }
          expect(invalid_date_transaction).not_to be_nil
        end
      end

      context "with contract ID that has no transactions" do
        it "returns empty array" do
          transactions = repository.find_transactions("DU123456", 999999)
          expect(transactions).to eq([])
        end
      end

      context "with account not in test data" do
        it "raises API error" do
          expect { repository.find_transactions("INVALID", 265598) }.to raise_error(
            Ibkr::ApiError,
            "Account INVALID not found in test data"
          )
        end
      end
    end
  end

  describe "test helper methods" do
    subject(:repository) { described_class.new(client) }

    describe "#set_test_data" do
      it "replaces the entire test data set" do
        new_data = {
          available_accounts: ["NEW001"],
          summaries: {},
          metadata: {},
          positions: {},
          transactions: {}
        }

        repository.set_test_data(new_data)
        expect(repository.discover_accounts).to eq(["NEW001"])
      end
    end

    describe "#add_test_account" do
      it "adds new account to available accounts list" do
        expect(repository.account_exists?("NEW123")).to be false

        repository.add_test_account("NEW123")
        expect(repository.account_exists?("NEW123")).to be true
      end

      it "does not duplicate existing accounts" do
        original_count = repository.discover_accounts.length

        repository.add_test_account("DU123456")
        expect(repository.discover_accounts.length).to eq(original_count)
      end

      it "adds account-specific data when provided" do
        recent_date = Date.today.to_s
        account_data = {
          summary: {net_liquidation_value: {amount: 75000.0, currency: "USD"}},
          metadata: {"id" => "NEW123", "accountType" => "PAPER"},
          positions: {"results" => [{"conid" => 999, "position" => 25}]},
          transactions: [{"date" => recent_date, "conid" => 999}]
        }

        repository.add_test_account("NEW123", account_data)

        summary = repository.find_summary("NEW123")
        expect(summary.net_liquidation_value[:amount]).to eq(75000.0)

        metadata = repository.find_metadata("NEW123")
        expect(metadata["accountType"]).to eq("PAPER")

        positions = repository.find_positions("NEW123")
        expect(positions["results"].first["conid"]).to eq(999)

        transactions = repository.find_transactions("NEW123", 999)
        expect(transactions).not_to be_empty
        expect(transactions.first["date"]).to eq(recent_date)
      end
    end

    describe "API error simulation" do
      describe "#simulate_api_error" do
        it "sets up error to be raised on next operation" do
          repository.simulate_api_error(Ibkr::RateLimitError, "Rate limited")

          expect { repository.find_summary("DU123456") }.to raise_error(
            Ibkr::RateLimitError,
            "Rate limited"
          )
        end

        it "uses default error class and message when not specified" do
          repository.simulate_api_error

          expect { repository.find_summary("DU123456") }.to raise_error(
            Ibkr::ApiError,
            "Simulated API error"
          )
        end

        it "affects all repository operations" do
          repository.simulate_api_error(Ibkr::AuthenticationError, "Not authenticated")

          expect { repository.find_summary("DU123456") }.to raise_error(Ibkr::AuthenticationError)
          expect { repository.find_metadata("DU123456") }.to raise_error(Ibkr::AuthenticationError)
          expect { repository.find_positions("DU123456") }.to raise_error(Ibkr::AuthenticationError)
          expect { repository.find_transactions("DU123456", 265598) }.to raise_error(Ibkr::AuthenticationError)
        end
      end

      describe "#clear_api_error" do
        it "removes simulated error allowing normal operation" do
          repository.simulate_api_error(Ibkr::ApiError, "Test error")
          repository.clear_api_error

          expect { repository.find_summary("DU123456") }.not_to raise_error
        end
      end
    end
  end

  describe "interface compliance" do
    subject(:repository) { described_class.new(client) }

    it "implements all required interface methods" do
      expect(repository).to respond_to(:find_summary)
      expect(repository).to respond_to(:find_metadata)
      expect(repository).to respond_to(:find_positions)
      expect(repository).to respond_to(:find_transactions)
      expect(repository).to respond_to(:discover_accounts)
      expect(repository).to respond_to(:account_exists?)
    end

    it "returns correct types from interface methods" do
      expect(repository.find_summary("DU123456")).to be_a(Ibkr::Accounts::Summary)
      expect(repository.find_metadata("DU123456")).to be_a(Hash)
      expect(repository.find_positions("DU123456")).to be_a(Hash)
      expect(repository.find_transactions("DU123456", 265598)).to be_an(Array)
      expect(repository.discover_accounts).to be_an(Array)
      expect(repository.account_exists?("DU123456")).to be_a(TrueClass).or be_a(FalseClass)
    end
  end

  describe "default test data structure" do
    subject(:repository) { described_class.new(client) }

    it "provides realistic default account summaries" do
      summary = repository.find_summary("DU123456")

      expect(summary.net_liquidation_value[:currency]).to eq("USD")
      expect(summary.buying_power[:amount]).to be > summary.available_funds[:amount]
      expect(summary.cushion[:value]).to be_between(0, 1)
    end

    it "provides realistic default positions" do
      positions = repository.find_positions("DU123456")
      apple_position = positions["results"].find { |p| p["description"] == "APPLE INC" }

      expect(apple_position["conid"]).to eq("265598")
      expect(apple_position["position"]).to be > 0
      expect(apple_position["market_value"]).to be > 0
      expect(apple_position["currency"]).to eq("USD")
    end

    it "provides realistic default transactions" do
      transactions = repository.find_transactions("DU123456", 265598)

      expect(transactions).not_to be_empty
      transactions.each do |transaction|
        expect(transaction["cur"]).to eq("USD")
        expect(transaction["date"]).to match(/\d{4}-\d{2}-\d{2}/)
        expect(transaction["type"]).to eq("Trades")
      end
    end
  end
end
