# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Ibkr Fluent Interface", type: :unit do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked IBKR API"

  describe "Module-level factory methods" do
    describe ".client" do
      it "creates a client with default account" do
        client = Ibkr.client("DU123456", live: false)

        expect(client).to be_instance_of(Ibkr::Client)
        expect(client.instance_variable_get(:@default_account_id)).to eq("DU123456")
        expect(client.instance_variable_get(:@live)).to be false
      end

      it "creates a client without default account" do
        client = Ibkr.client(live: true)

        expect(client).to be_instance_of(Ibkr::Client)
        expect(client.instance_variable_get(:@default_account_id)).to be_nil
        expect(client.instance_variable_get(:@live)).to be true
      end
    end

    describe ".discover_accounts" do
      it "creates a client for account discovery" do
        client = Ibkr.discover_accounts(live: false)

        expect(client).to be_instance_of(Ibkr::Client)
        expect(client.instance_variable_get(:@default_account_id)).to be_nil
        expect(client.instance_variable_get(:@live)).to be false
      end
    end

    describe ".connect" do
      it "creates and authenticates a client" do
        client = Ibkr.connect("DU123456", live: false)

        expect(client).to be_instance_of(Ibkr::Client)
        expect(client.authenticated?).to be true
        expect(client.account_id).to eq("DU123456")
      end
    end

    describe ".connect_and_discover" do
      it "creates, authenticates, and discovers accounts" do
        client = Ibkr.connect_and_discover(live: false)

        expect(client).to be_instance_of(Ibkr::Client)
        expect(client.authenticated?).to be true
        expect(client.available_accounts).to include("DU123456")
      end
    end
  end

  describe "Client chainable methods" do
    let(:client) { Ibkr.client("DU123456", live: false) }

    describe "#authenticate!" do
      it "authenticates and returns self" do
        result = client.authenticate!

        expect(result).to be(client)
        expect(client.authenticated?).to be true
      end
    end

    describe "#with_account" do
      before do
        client.authenticate!
        # Mock multiple accounts
        client.instance_variable_set(:@available_accounts, ["DU123456", "DU789012"])
      end

      it "switches account and returns self" do
        result = client.with_account("DU789012")

        expect(result).to be(client)
        expect(client.account_id).to eq("DU789012")
      end
    end

    describe "#portfolio" do
      before { client.authenticate! }

      it "returns a chainable accounts proxy" do
        portfolio = client.portfolio

        expect(portfolio).to be_instance_of(Ibkr::ChainableAccountsProxy)
      end
    end

    describe "#accounts_fluent" do
      before { client.authenticate! }

      it "returns a chainable accounts proxy" do
        accounts = client.accounts_fluent

        expect(accounts).to be_instance_of(Ibkr::ChainableAccountsProxy)
      end
    end
  end

  describe "ChainableAccountsProxy" do
    let(:client) { Ibkr.connect("DU123456", live: false) }
    let(:proxy) { client.portfolio }
    let(:mock_accounts_service) { client.accounts }

    before do
      # Mock the accounts service methods to avoid real API calls
      allow(mock_accounts_service).to receive(:summary).and_return(
        Ibkr::Accounts::Summary.new(
          account_id: "DU123456",
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
        )
      )

      allow(mock_accounts_service).to receive(:positions).and_return(
        {"results" => [{"conid" => "265598", "position" => 100, "description" => "APPLE INC"}]}
      )

      allow(mock_accounts_service).to receive(:transactions).and_return(
        [{"date" => "2024-08-14", "desc" => "AAPL BUY", "amt" => -15025.00}]
      )

      allow(mock_accounts_service).to receive(:get).and_return(
        {"id" => "DU123456", "accountType" => "DEMO"}
      )
    end

    describe "direct methods" do
      it "delegates summary to accounts service" do
        summary = proxy.summary

        expect(summary).to be_instance_of(Ibkr::Accounts::Summary)
        expect(summary.account_id).to eq("DU123456")
      end

      it "delegates positions to accounts service" do
        positions = proxy.positions

        expect(positions).to be_a(Hash)
        expect(positions).to have_key("results")
      end

      it "delegates transactions to accounts service" do
        transactions = proxy.transactions(265598, 30)

        expect(transactions).to be_an(Array)
      end

      it "delegates metadata to accounts service" do
        metadata = proxy.metadata

        expect(metadata).to be_a(Hash)
        expect(metadata["id"]).to eq("DU123456")
      end
    end

    describe "chainable methods" do
      it "chains page selection" do
        result = proxy.with_page(2)

        expect(result).to be(proxy)
        expect(proxy.instance_variable_get(:@page)).to eq(2)
      end

      it "chains sorting options" do
        result = proxy.sorted_by("market_value", "desc")

        expect(result).to be(proxy)
        expect(proxy.instance_variable_get(:@sort_field)).to eq("market_value")
        expect(proxy.instance_variable_get(:@sort_direction)).to eq("desc")
      end

      it "chains period selection" do
        result = proxy.for_period(60)

        expect(result).to be(proxy)
        expect(proxy.instance_variable_get(:@period_days)).to eq(60)
      end

      it "chains contract selection" do
        result = proxy.for_contract(265598)

        expect(result).to be(proxy)
        expect(proxy.instance_variable_get(:@contract_id)).to eq(265598)
      end
    end

    describe "terminal methods with options" do
      it "executes positions with accumulated options" do
        positions = proxy
          .with_page(1)
          .sorted_by("market_value", "desc")
          .positions_with_options

        expect(positions).to be_a(Hash)

        # Verify the underlying service was called with correct options
        expect(client.accounts).to have_received(:positions).with(
          page: 1,
          sort: "market_value",
          direction: "desc"
        )
      end

      it "executes transactions with accumulated options" do
        transactions = proxy
          .for_contract(265598)
          .for_period(45)
          .transactions_with_options

        expect(transactions).to be_an(Array)

        # Verify the underlying service was called with correct options
        expect(client.accounts).to have_received(:transactions).with(265598, 45)
      end

      it "raises error when contract not specified for transactions" do
        expect {
          proxy.for_period(30).transactions_with_options
        }.to raise_error(ArgumentError, /Contract ID must be specified/)
      end
    end

    describe "method delegation" do
      it "delegates unknown methods to accounts service" do
        allow(client.accounts).to receive(:custom_method).and_return("custom_result")

        result = proxy.custom_method("arg1", "arg2")

        expect(result).to eq("custom_result")
        expect(client.accounts).to have_received(:custom_method).with("arg1", "arg2")
      end

      it "handles respond_to_missing correctly" do
        allow(client.accounts).to receive(:respond_to?).with(:custom_method, false).and_return(true)

        expect(proxy.respond_to?(:custom_method)).to be true
      end
    end
  end

  describe "End-to-end fluent workflows" do
    it "supports complete single-account fluent workflow" do
      # Create, authenticate, and get summary in one chain
      client = Ibkr.connect("DU123456", live: false)

      # Mock the accounts service
      allow(client.accounts).to receive(:summary).and_return(
        Ibkr::Accounts::Summary.new(
          account_id: "DU123456",
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
        )
      )

      summary = client.portfolio.summary

      expect(summary).to be_instance_of(Ibkr::Accounts::Summary)
      expect(summary.account_id).to eq("DU123456")
    end

    it "supports multi-account discovery and switching" do
      # Mock multiple accounts response
      accounts_response = {"accounts" => ["DU123456", "DU789012"]}
      stub_request(:get, "#{base_url}/v1/api/iserver/accounts")
        .to_return(
          status: 200,
          body: accounts_response.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      # Discover accounts, switch, and get positions
      client = Ibkr.connect_and_discover(live: false)
        .with_account("DU789012")

      # Mock positions method
      allow(client.accounts).to receive(:positions).and_return(
        {"results" => [{"conid" => "265598", "position" => 100, "description" => "APPLE INC"}]}
      )

      positions = client.portfolio
        .with_page(1)
        .sorted_by("market_value", "desc")
        .positions_with_options

      expect(positions).to be_a(Hash)
      expect(positions).to have_key("results")
    end

    it "supports complex transaction queries" do
      client = Ibkr.connect("DU123456", live: false)

      # Mock transactions method
      allow(client.accounts).to receive(:transactions).and_return(
        [{"date" => "2024-08-14", "desc" => "AAPL BUY", "amt" => -15025.00}]
      )

      transactions = client.portfolio
        .for_contract(265598)
        .for_period(90)
        .transactions_with_options

      expect(transactions).to be_an(Array)
    end

    it "maintains backward compatibility with existing API" do
      # Old way should still work
      client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
      client.authenticate

      # Mock summary for old way
      allow(client.accounts).to receive(:summary).and_return(
        Ibkr::Accounts::Summary.new(
          account_id: "DU123456",
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
        )
      )

      summary = client.accounts.summary
      expect(summary).to be_instance_of(Ibkr::Accounts::Summary)

      # New fluent way should produce same result
      fluent_client = Ibkr.connect("DU123456", live: false)

      # Mock summary for fluent way
      allow(fluent_client.accounts).to receive(:summary).and_return(
        Ibkr::Accounts::Summary.new(
          account_id: "DU123456",
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
        )
      )

      fluent_summary = fluent_client.portfolio.summary

      expect(fluent_summary.account_id).to eq(summary.account_id)
    end
  end
end
