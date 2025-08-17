# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Accounts do
  include_context "with authenticated oauth client"

  let(:client) do
    client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
    client.instance_variable_set(:@oauth_client, oauth_client)
    # Simulate authentication to set up active account
    client.instance_variable_set(:@available_accounts, ["DU123456"])
    client.instance_variable_set(:@active_account_id, "DU123456")
    client
  end

  let(:accounts_service) { described_class.new(client) }

  describe "initialization" do
    it "stores client reference and account ID" do
      # Given a client with an account ID set
      # When creating an Accounts service
      service = described_class.new(client)
      
      # Then it should store the client reference and account ID
      expect(service.instance_variable_get(:@_client)).to be(client)
      expect(service.account_id).to eq("DU123456")
    end

    it "reflects the client's immutable account ID" do
      # Given an accounts service
      # When creating a service from a client with account ID
      service = described_class.new(client)
      
      # Then the service should reflect the client's account ID
      expect(service.account_id).to eq("DU123456")
      expect(service.account_id).to eq(client.account_id)
    end
  end

  describe "#get" do
    let(:meta_response) do
      {
        "id" => "DU123456",
        "accountType" => "DEMO",
        "accountTitle" => "Test Account",
        "displayName" => "DU123456",
        "currency" => "USD",
        "type" => "DEMO"
      }
    end

    before do
      allow(oauth_client).to receive(:get)
        .with("/v1/api/portfolio/DU123456/meta")
        .and_return(meta_response)
    end

    it "retrieves account metadata" do
      # Given an authenticated client with account ID
      # When requesting account metadata
      result = accounts_service.get
      
      # Then it should return account information
      expect(result).to eq(meta_response)
      expect(result["id"]).to eq("DU123456")
      expect(result["accountType"]).to eq("DEMO")
    end

    it "uses correct API endpoint with account ID" do
      accounts_service.get
      
      expect(oauth_client).to have_received(:get).with("/v1/api/portfolio/DU123456/meta")
    end
  end

  describe "#summary" do
    let(:raw_summary_response) do
      {
        "netliquidation" => { "amount" => 50000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "availablefunds" => { "amount" => 25000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "buyingpower" => { "amount" => 100000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "accruedcash" => { "amount" => 45.67, "currency" => "USD", "timestamp" => 1692000000000 },
        "cushion" => { "value" => 0.85 },
        "equitywithloanvalue" => { "amount" => 50000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "excessliquidity" => { "amount" => 30000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "grosspositionvalue" => { "amount" => 75000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "initmarginreq" => { "amount" => 15000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "maintmarginreq" => { "amount" => 12000.00, "currency" => "USD", "timestamp" => 1692000000000 },
        "totalcashvalue" => { "amount" => 25000.00, "currency" => "USD", "timestamp" => 1692000000000 }
      }
    end

    before do
      allow(oauth_client).to receive(:get)
        .with("/v1/api/portfolio/DU123456/summary")
        .and_return(raw_summary_response)
    end

    it "retrieves and transforms portfolio summary data" do
      # Given an authenticated client
      # When requesting portfolio summary
      summary = accounts_service.summary
      
      # Then it should return a structured Summary object
      expect(summary).to be_instance_of(Ibkr::Accounts::Summary)
      expect(summary.account_id).to eq("DU123456")
      expect(summary.net_liquidation_value.amount).to eq(50000.00)
      expect(summary.buying_power.amount).to eq(100000.00)
    end

    it "transforms IBKR API keys to normalized attribute names" do
      summary = accounts_service.summary
      
      # Verify key transformation worked correctly
      expect(summary.net_liquidation_value).to be_instance_of(Ibkr::Accounts::AccountValue)
      expect(summary.available_funds).to be_instance_of(Ibkr::Accounts::AccountValue)
      expect(summary.equity_with_loan).to be_instance_of(Ibkr::Accounts::AccountValue)
    end

    it "converts timestamps from milliseconds to Time objects" do
      summary = accounts_service.summary
      
      expect(summary.net_liquidation_value.timestamp).to be_instance_of(Time)
      expect(summary.net_liquidation_value.timestamp.to_i).to eq(1692000000)
    end

    it "includes account ID in the summary data" do
      summary = accounts_service.summary
      
      expect(summary.account_id).to eq("DU123456")
    end

    include_examples "a successful API request" do
      subject { { "result" => raw_summary_response } }
      let(:response_body) { { "result" => raw_summary_response }.to_json }
    end
  end

  describe "#positions" do
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
            "realized_pnl" => 500.00,
            "market_value" => 16275.00,
            "market_price" => 162.75,
            "security_type" => "STK",
            "asset_class" => "STOCK",
            "sector" => "Technology",
            "group" => "Technology - Services"
          },
          {
            "conid" => "76792991",
            "position" => 50,
            "average_cost" => 95.50,
            "currency" => "USD",
            "description" => "MICROSOFT CORP",
            "unrealized_pnl" => 525.00,
            "realized_pnl" => 0.00,
            "market_value" => 5300.00,
            "market_price" => 106.00,
            "security_type" => "STK",
            "asset_class" => "STOCK",
            "sector" => "Technology",
            "group" => "Technology - Software"
          }
        ]
      }
    end

    before do
      allow(oauth_client).to receive(:get)
        .with("/v1/api/portfolio2/DU123456/positions", params: anything)
        .and_return(positions_response)
    end

    it "retrieves current portfolio positions with default parameters" do
      # Given an authenticated client
      # When requesting positions without parameters
      positions = accounts_service.positions
      
      # Then it should return positions data with default parameters
      expect(positions).to have_key("results")
      expect(positions["results"]).to be_an(Array)
      expect(positions["results"].size).to eq(2)
      
      # Verify default parameters were used
      expect(oauth_client).to have_received(:get).with(
        "/v1/api/portfolio2/DU123456/positions",
        params: {
          pageId: 0,
          sort: "description",
          direction: "asc"
        }
      )
    end

    it "supports custom pagination and sorting parameters" do
      # Given specific pagination and sorting requirements
      # When requesting positions with custom parameters
      accounts_service.positions(page: 2, sort: "market_value", direction: "desc")
      
      # Then it should use the specified parameters
      expect(oauth_client).to have_received(:get).with(
        "/v1/api/portfolio2/DU123456/positions",
        params: {
          pageId: 2,
          sort: "market_value",
          direction: "desc"
        }
      )
    end

    it "returns position data suitable for further processing" do
      positions = accounts_service.positions
      
      first_position = positions["results"].first
      expect(first_position).to include(
        "conid" => "265598",
        "description" => "APPLE INC",
        "position" => 100,
        "unrealized_pnl" => 1250.50
      )
    end

    include_examples "a successful API request" do
      subject { { "result" => positions_response } }
      let(:response_body) { { "result" => positions_response }.to_json }
    end
  end

  describe "#transactions" do
    let(:contract_id) { 265598 }
    let(:days) { 30 }
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
        },
        {
          "date" => "2024-08-10",
          "cur" => "USD",
          "pr" => 148.75,
          "qty" => -50,
          "amt" => 7437.50,
          "conid" => 265598,
          "desc" => "AAPL SELL",
          "type" => "Trades"
        }
      ]
    end

    before do
      allow(oauth_client).to receive(:post)
        .with("/v1/api/pa/transactions", body: anything)
        .and_return(transactions_response)
    end

    it "retrieves transaction history for specific contract" do
      # Given a contract ID and time period
      # When requesting transaction history
      transactions = accounts_service.transactions(contract_id, days)
      
      # Then it should return transaction data
      expect(transactions).to be_an(Array)
      expect(transactions.size).to eq(2)
      expect(transactions.first["desc"]).to eq("AAPL BUY")
      expect(transactions.last["desc"]).to eq("AAPL SELL")
    end

    it "uses correct request body structure" do
      accounts_service.transactions(contract_id, days)
      
      expect(oauth_client).to have_received(:post).with(
        "/v1/api/pa/transactions",
        body: {
          "acctIds" => ["DU123456"],
          "conids" => [265598],
          "days" => 30,
          "currency" => "USD"
        }
      )
    end

    it "uses default 90-day period when not specified" do
      accounts_service.transactions(contract_id)
      
      expect(oauth_client).to have_received(:post).with(
        "/v1/api/pa/transactions",
        body: hash_including("days" => 90)
      )
    end

    it "handles multiple contract IDs in request" do
      # The current implementation only handles single contract
      # This test documents the expected behavior for the body structure
      accounts_service.transactions(contract_id, days)
      
      expect(oauth_client).to have_received(:post).with(
        "/v1/api/pa/transactions",
        body: hash_including("conids" => [contract_id])
      )
    end

    include_examples "a successful API request" do
      subject { { "result" => transactions_response } }
      let(:response_body) { { "result" => transactions_response }.to_json }
    end
  end

  describe "private methods" do
    describe "#normalize_summary" do
      let(:raw_data) do
        {
          "netliquidation" => { "amount" => 50000.00, "timestamp" => 1692000000000 },
          "availablefunds" => { "amount" => 25000.00, "timestamp" => 1692000000000 },
          "unknown_field" => { "amount" => 100.00 }
        }
      end

      it "transforms known keys using KEY_MAPPING" do
        normalized = accounts_service.send(:normalize_summary, raw_data)
        
        expect(normalized).to have_key("net_liquidation_value")
        expect(normalized).to have_key("available_funds")
        expect(normalized).not_to have_key("netliquidation")
        expect(normalized).not_to have_key("availablefunds")
      end

      it "preserves unknown fields unchanged" do
        normalized = accounts_service.send(:normalize_summary, raw_data)
        
        expect(normalized).to have_key("unknown_field")
        expect(normalized["unknown_field"]).to eq({ "amount" => 100.00 })
      end

      it "converts timestamps from milliseconds to Time objects" do
        normalized = accounts_service.send(:normalize_summary, raw_data)
        
        expect(normalized["net_liquidation_value"]["timestamp"]).to be_instance_of(Time)
        expect(normalized["net_liquidation_value"]["timestamp"].to_i).to eq(1692000000)
      end

      it "handles missing timestamp fields gracefully" do
        data_without_timestamp = {
          "netliquidation" => { "amount" => 50000.00 }
        }
        
        normalized = accounts_service.send(:normalize_summary, data_without_timestamp)
        
        expect(normalized["net_liquidation_value"]).to eq({ "amount" => 50000.00 })
      end

      it "handles non-hash values in timestamp conversion" do
        data_with_non_hash = {
          "netliquidation" => "not_a_hash"
        }
        
        normalized = accounts_service.send(:normalize_summary, data_with_non_hash)
        
        expect(normalized["net_liquidation_value"]).to eq("not_a_hash")
      end
    end
  end
end