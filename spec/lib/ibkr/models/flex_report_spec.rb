# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Models::FlexReport do
  # This is the structure that build_report_model creates
  let(:flex_report_data) do
    {
      reference_code: "TEST_REF_123456",
      report_type: "AF",
      generated_at: Time.now.to_i * 1000,
      account_id: "DU123456",
      data: {
        query_name: "Portfolio Activity Report",
        type: "AF",
        accounts: ["DU123456"],
        transactions: [
          {
            transaction_id: "TX001",
            account_id: "DU123456",
            symbol: "AAPL",
            trade_date: Date.parse("2024-01-15"),
            settle_date: Date.parse("2024-01-17"),
            quantity: 100.0,
            price: 150.25,
            proceeds: 15025.00,
            commission: 1.00,
            currency: "USD",
            asset_class: "STK"
          },
          {
            transaction_id: "TX002",
            account_id: "DU123456",
            symbol: "GOOGL",
            trade_date: Date.parse("2024-01-20"),
            settle_date: Date.parse("2024-01-22"),
            quantity: 50.0,
            price: 140.50,
            proceeds: 7025.00,
            commission: 1.00,
            currency: "USD",
            asset_class: "STK"
          }
        ],
        positions: [
          {
            account_id: "DU123456",
            symbol: "AAPL",
            position: 100.0,
            market_price: 155.0,
            market_value: 15500.0,
            average_cost: 150.25,
            unrealized_pnl: 475.0,
            realized_pnl: 0,
            currency: "USD",
            asset_class: "STK"
          }
        ],
        cash_report: [
          {
            account_id: "DU123456",
            currency: "USD",
            starting_cash: 100000.0,
            ending_cash: 95234.50,
            deposits: 0,
            withdrawals: 0
          }
        ],
        performance: [
          {
            account_id: "DU123456",
            period: "2024-01-31",
            nav_start: 115234.50,
            nav_end: 115234.50,
            realized_pnl: 2442.0,
            unrealized_pnl: 0.0
          }
        ]
      }
    }
  end

  describe "initialization" do
    it "creates a valid FlexReport model" do
      report = described_class.new(flex_report_data)
      
      expect(report).to be_a(described_class)
      expect(report.reference_code).to eq("TEST_REF_123456")
      expect(report.report_type).to eq("AF")
      expect(report.account_id).to eq("DU123456")
      expect(report.generated_at).to be_a(Time)
    end

    it "stores the parsed data" do
      report = described_class.new(flex_report_data)
      
      expect(report.data).to be_a(Hash)
      expect(report.data[:query_name]).to eq("Portfolio Activity Report")
      expect(report.data[:accounts]).to eq(["DU123456"])
    end

    it "validates required fields" do
      expect {
        described_class.new({})
      }.to raise_error(Dry::Struct::Error, /:reference_code is missing/)
    end
  end

  describe "status methods" do
    it "indicates ready status" do
      report = described_class.new(flex_report_data)
      expect(report).to be_ready
      expect(report).not_to be_processing
      expect(report).not_to be_expired
    end

    it "checks for data presence" do
      report = described_class.new(flex_report_data)
      expect(report.has_data?).to be true
    end
  end

  describe "convenience accessors" do
    let(:report) { described_class.new(flex_report_data) }

    it "provides access to trades" do
      expect(report.trades).to be_an(Array)
      expect(report.trades.size).to eq(2)
      expect(report.trades.first[:symbol]).to eq("AAPL")
    end

    it "provides access to positions" do
      expect(report.positions).to be_an(Array)
      expect(report.positions.size).to eq(1)
      expect(report.positions.first[:symbol]).to eq("AAPL")
      expect(report.positions.first[:unrealized_pnl]).to eq(475.0)
    end

    it "provides access to cash reports" do
      expect(report.cash_reports).to be_an(Array)
      expect(report.cash_reports.size).to eq(1)
      expect(report.cash_reports.first[:ending_cash]).to eq(95234.50)
    end

    it "provides access to metadata" do
      expect(report.query_name).to eq("Portfolio Activity Report")
      expect(report.period).to be_nil # Not in our test data
    end

    it "handles missing data gracefully" do
      minimal_report = described_class.new(
        reference_code: "MIN_REF",
        report_type: "AF",
        generated_at: Time.now.to_i * 1000,
        data: {}
      )
      
      expect(minimal_report.trades).to eq([])
      expect(minimal_report.positions).to eq([])
      expect(minimal_report.cash_reports).to eq([])
    end
  end

  describe "data normalization" do
    it "handles single trade as array" do
      single_trade_data = flex_report_data.dup
      single_trade_data[:data] = flex_report_data[:data].dup
      single_trade_data[:data][:transactions] = {
        transaction_id: "TX001",
        symbol: "AAPL"
      }
      
      report = described_class.new(single_trade_data)
      expect(report.trades).to be_an(Array)
      expect(report.trades.size).to eq(1)
    end

    it "handles nil transactions" do
      no_trades_data = flex_report_data.dup
      no_trades_data[:data] = flex_report_data[:data].dup
      no_trades_data[:data][:transactions] = nil
      
      report = described_class.new(no_trades_data)
      expect(report.trades).to eq([])
    end
  end

  describe "integration with Flex service" do
    it "works with data from Flex.parse_report" do
      # This simulates what build_report_model does
      report_data = {
        reference_code: "2332907389",
        report_type: "AF",
        generated_at: Time.now.to_i * 1000,
        account_id: "DU123456",
        data: {
          query_name: "Test Report",
          type: "AF",
          accounts: ["DU123456"],
          transactions: Array.new(5) do |i|
            {
              transaction_id: "TX#{i}",
              account_id: "DU123456",
              symbol: ["AAPL", "MSFT", "GOOGL"][i % 3],
              trade_date: Date.today - i,
              quantity: 100.0,
              price: 150.0 + i,
              currency: "USD",
              asset_class: "STK"
            }
          end,
          positions: [],
          cash_report: nil,
          performance: nil
        }
      }
      
      report = described_class.new(report_data)
      
      expect(report.reference_code).to eq("2332907389")
      expect(report.trades.size).to eq(5)
      expect(report.account_id).to eq("DU123456")
    end
  end

  describe "FlexTransaction model" do
    let(:transaction_data) do
      {
        transaction_id: "987654321",
        account_id: "DU123456",
        symbol: "AAPL",
        trade_date: Date.parse("2024-01-15"),
        settle_date: Date.parse("2024-01-17"),
        quantity: 100.0,
        price: 150.50,
        proceeds: 15050.0,
        commission: 1.0,
        currency: "USD",
        asset_class: "STK"
      }
    end

    it "creates a valid transaction model" do
      transaction = Ibkr::Models::FlexTransaction.new(transaction_data)
      
      expect(transaction.transaction_id).to eq("987654321")
      expect(transaction.symbol).to eq("AAPL")
      expect(transaction.quantity).to eq(100.0)
      expect(transaction.price).to eq(150.50)
    end

    it "calculates net amount" do
      transaction = Ibkr::Models::FlexTransaction.new(transaction_data)
      expect(transaction.net_amount).to eq(15049.0) # proceeds - commission
    end

    it "identifies asset types" do
      stock_transaction = Ibkr::Models::FlexTransaction.new(transaction_data)
      expect(stock_transaction).to be_stock
      expect(stock_transaction).not_to be_option
      
      option_data = transaction_data.merge(asset_class: "OPT")
      option_transaction = Ibkr::Models::FlexTransaction.new(option_data)
      expect(option_transaction).to be_option
      expect(option_transaction).not_to be_stock
    end
  end

  describe "FlexPosition model" do
    let(:position_data) do
      {
        account_id: "DU123456",
        symbol: "AAPL",
        position: 100.0,
        market_price: 155.0,
        market_value: 15500.0,
        average_cost: 150.25,
        unrealized_pnl: 475.0,
        realized_pnl: 0.0,
        currency: "USD",
        asset_class: "STK"
      }
    end

    it "creates a valid position model" do
      position = Ibkr::Models::FlexPosition.new(position_data)
      
      expect(position.symbol).to eq("AAPL")
      expect(position.position).to eq(100.0)
      expect(position.unrealized_pnl).to eq(475.0)
    end

    it "calculates position metrics" do
      position = Ibkr::Models::FlexPosition.new(position_data)
      
      expect(position.total_pnl).to eq(475.0) # unrealized + realized
      expect(position).to be_long
      expect(position).not_to be_short
      expect(position.pnl_percentage).to be_within(0.01).of(3.16) # (475 / 15025) * 100
    end
  end

  describe "FlexCashReport model" do
    let(:cash_data) do
      {
        account_id: "DU123456",
        currency: "USD",
        starting_cash: 100000.0,
        ending_cash: 95234.50,
        deposits: 0.0,
        withdrawals: 0.0,
        dividends: 125.0,
        interest: 15.0,
        fees: -45.0,
        realized_pnl: 2442.0
      }
    end

    it "creates a valid cash report model" do
      cash_report = Ibkr::Models::FlexCashReport.new(cash_data)
      
      expect(cash_report.account_id).to eq("DU123456")
      expect(cash_report.ending_cash).to eq(95234.50)
      expect(cash_report.currency).to eq("USD")
    end

    it "calculates net change" do
      cash_report = Ibkr::Models::FlexCashReport.new(cash_data)
      expect(cash_report.net_change).to eq(-4765.50) # ending - starting
    end
  end

  describe "FlexPerformance model" do
    let(:performance_data) do
      {
        account_id: "DU123456",
        period: "LastMonth",
        nav_start: 100000.0,
        nav_end: 115234.50,
        deposits: 0.0,
        withdrawals: 0.0,
        realized_pnl: 2442.0,
        unrealized_pnl: 1323.50,
        dividends: 125.0,
        interest: 15.0,
        commissions: -245.0
      }
    end

    it "creates a valid performance model" do
      performance = Ibkr::Models::FlexPerformance.new(performance_data)
      
      expect(performance.account_id).to eq("DU123456")
      expect(performance.nav_end).to eq(115234.50)
      expect(performance.realized_pnl).to eq(2442.0)
    end

    it "calculates performance metrics" do
      performance = Ibkr::Models::FlexPerformance.new(performance_data)
      
      expect(performance.total_pnl).to eq(3765.50) # realized + unrealized
      expect(performance.net_performance).to eq(15234.50) # nav_end - nav_start - deposits + withdrawals
      expect(performance.return_percentage).to be_within(0.01).of(15.23) # (net_performance / start) * 100
    end
  end
end