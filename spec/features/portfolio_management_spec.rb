# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Portfolio Management Operations", type: :feature do
  include_context "with authenticated oauth client"

  let(:client) do
    client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
    client.oauth_client = oauth_client
    # Simulate authentication to set up active account
    client.set_available_accounts(["DU123456"])
    client.set_active_account_for_test("DU123456")
    client
  end

  let(:accounts_service) { client.accounts }

  describe "User views their portfolio summary" do
    let(:summary_response) do
      {
        "netliquidation" => {"amount" => 50000.00, "currency" => "USD", "timestamp" => 1692000000000},
        "availablefunds" => {"amount" => 25000.00, "currency" => "USD", "timestamp" => 1692000000000},
        "buyingpower" => {"amount" => 100000.00, "currency" => "USD", "timestamp" => 1692000000000}
      }
    end

    before do
      allow(oauth_client).to receive(:get)
        .with("/v1/api/portfolio/DU123456/summary")
        .and_return(summary_response)
    end

    it "retrieves a comprehensive overview of their account value and buying power" do
      # Given an authenticated user with an active portfolio
      # When they request their portfolio summary
      summary = accounts_service.summary

      # Then they should see their current account value, available funds, and buying power
      expect(summary).to be_instance_of(Ibkr::Accounts::Summary)
      expect(summary.net_liquidation_value.amount).to eq(50000.00)
      expect(summary.available_funds.amount).to eq(25000.00)
      expect(summary.buying_power.amount).to eq(100000.00)
      expect(summary.account_id).to eq("DU123456")
    end

    it "shows time-sensitive data with proper timestamps" do
      # Given portfolio data with timestamps
      # When the user views their summary
      summary = accounts_service.summary

      # Then timestamps should be properly converted to Time objects
      expect(summary.net_liquidation_value.timestamp).to be_instance_of(Time)
      expect(summary.net_liquidation_value.timestamp.to_i).to eq(1692000000)
    end
  end

  describe "User explores their current positions" do
    let(:positions_response) do
      {
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
          }
        ]
      }
    end

    before do
      allow(oauth_client).to receive(:get)
        .with("/v1/api/portfolio2/DU123456/positions", params: anything)
        .and_return(positions_response)
    end

    it "views all current stock and option positions with performance metrics" do
      # Given a user with active positions in their portfolio
      # When they request their current positions
      positions = accounts_service.positions

      # Then they should see detailed information about each position
      expect(positions).to have_key("results")
      expect(positions["results"]).to be_an(Array)
      expect(positions["results"].first).to include(
        "conid" => "265598",
        "position" => 100,
        "description" => "APPLE INC",
        "unrealized_pnl" => 1250.50
      )
    end

    it "can sort and paginate through large position lists" do
      # Given a user with many positions
      # When they request positions with specific sorting and pagination
      accounts_service.positions(page: 1, sort: "market_value", direction: "desc")

      # Then the request should include proper sorting parameters
      expect(oauth_client).to have_received(:get).with(
        "/v1/api/portfolio2/DU123456/positions",
        params: {
          pageId: 1,
          sort: "market_value",
          direction: "desc"
        }
      )
    end

    it "handles empty portfolios gracefully" do
      # Given a user with no current positions
      allow(oauth_client).to receive(:get).and_return({"results" => []})

      # When they request their positions
      positions = accounts_service.positions

      # Then they should receive an empty but valid response
      expect(positions).to have_key("results")
      expect(positions["results"]).to be_empty
    end
  end

  describe "User reviews transaction history" do
    let(:transactions_response) do
      [
        {
          "date" => "2024-08-14",
          "cur" => "USD",
          "pr" => 150.25,
          "qty" => 100,
          "amt" => -15025.00,
          "conid" => 265598,
          "desc" => "AAPL BUY",
          "type" => "Trades"
        }
      ]
    end

    before do
      allow(oauth_client).to receive(:post)
        .with("/v1/api/pa/transactions", body: anything)
        .and_return(transactions_response)
    end

    it "retrieves transaction history for specific securities" do
      # Given a user wants to review their trading activity
      contract_id = 265598

      # When they request transaction history for a specific security
      transactions = accounts_service.transactions(contract_id, 30)

      # Then they should see detailed transaction records
      expect(transactions).to be_an(Array)
      expect(transactions.first).to include(
        "date" => "2024-08-14",
        "desc" => "AAPL BUY",
        "amt" => -15025.00,
        "qty" => 100
      )
    end

    it "allows filtering by time period" do
      # Given a user wants transactions from a specific time period
      contract_id = 265598
      days = 90

      # When they request transactions with a specific day range
      accounts_service.transactions(contract_id, days)

      # Then the request should include the correct time filter
      expect(oauth_client).to have_received(:post).with(
        "/v1/api/pa/transactions",
        body: hash_including(
          "acctIds" => ["DU123456"],
          "conids" => [265598],
          "days" => 90,
          "currency" => "USD"
        )
      )
    end
  end

  describe "User handles portfolio data errors" do
    it "receives clear error messages when portfolio data is unavailable" do
      # Given the IBKR API is experiencing issues
      allow(oauth_client).to receive(:get).and_raise("Portfolio data temporarily unavailable")

      # When the user tries to access their portfolio
      # Then they should receive a clear error message
      expect { accounts_service.summary }.to raise_error(/Portfolio data temporarily unavailable/)
    end

    it "handles network timeouts gracefully" do
      # Given a network timeout occurs
      allow(oauth_client).to receive(:get).and_raise(Faraday::TimeoutError)

      # When the user tries to access portfolio data
      # Then the error should be properly surfaced
      expect { accounts_service.summary }.to raise_error(Faraday::TimeoutError)
    end
  end
end
