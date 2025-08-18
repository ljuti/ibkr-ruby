# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Services::Flex do
  let(:client) { instance_double(Ibkr::Client, config: config) }
  let(:config) { instance_double(Ibkr::Configuration, flex_token: "test_token") }
  let(:flex_service) { described_class.new(client) }
  let(:flex_client) { instance_double(Ibkr::Flex) }
  
  let(:query_id) { "123456" }
  let(:reference_code) { "ABC123DEF456" }
  
  before do
    allow(Ibkr::Flex).to receive(:new).and_return(flex_client)
  end

  describe "initialization" do
    it "creates internal Flex client with configuration" do
      expect(Ibkr::Flex).to receive(:new).with(
        token: nil,
        config: config,
        client: client
      ).and_return(flex_client)
      
      described_class.new(client)
    end
    
    it "accepts explicit token" do
      expect(Ibkr::Flex).to receive(:new).with(
        token: "explicit_token",
        config: config,
        client: client
      ).and_return(flex_client)
      
      described_class.new(client, token: "explicit_token")
    end
  end

  describe "#generate_report" do
    it "delegates to Flex client" do
      expect(flex_client).to receive(:generate_report).with(query_id).and_return(reference_code)
      
      result = flex_service.generate_report(query_id)
      expect(result).to eq(reference_code)
    end
  end

  describe "#get_report" do
    it "delegates to Flex client with default format" do
      report_data = { data: "test" }
      expect(flex_client).to receive(:get_report).with(reference_code, format: :hash).and_return(report_data)
      
      result = flex_service.get_report(reference_code)
      expect(result).to eq(report_data)
    end
    
    it "passes format option" do
      expect(flex_client).to receive(:get_report).with(reference_code, format: :raw).and_return("<xml/>")
      
      result = flex_service.get_report(reference_code, format: :raw)
      expect(result).to eq("<xml/>")
    end
  end

  describe "#generate_and_fetch" do
    it "delegates to Flex client with default parameters" do
      report_data = { data: "test" }
      expect(flex_client).to receive(:generate_and_fetch).with(
        query_id,
        max_wait: 60,
        poll_interval: 5
      ).and_return(report_data)
      
      result = flex_service.generate_and_fetch(query_id)
      expect(result).to eq(report_data)
    end
    
    it "passes custom wait and poll parameters" do
      report_data = { data: "test" }
      expect(flex_client).to receive(:generate_and_fetch).with(
        query_id,
        max_wait: 120,
        poll_interval: 10
      ).and_return(report_data)
      
      result = flex_service.generate_and_fetch(query_id, max_wait: 120, poll_interval: 10)
      expect(result).to eq(report_data)
    end
  end

  describe "#transactions_report" do
    let(:transaction_data) do
      {
        transactions: [
          {
            transaction_id: "123",
            account_id: "DU123456",
            symbol: "AAPL",
            trade_date: Date.parse("2024-01-15"),
            settle_date: Date.parse("2024-01-17"),
            quantity: 100,
            price: 150.50,
            proceeds: 15050,
            commission: -1.00,
            currency: "USD",
            asset_class: "STK"
          }
        ]
      }
    end
    
    it "returns FlexTransaction models" do
      expect(flex_client).to receive(:generate_and_fetch).with(query_id, max_wait: 60, poll_interval: 5).and_return(transaction_data)
      
      result = flex_service.transactions_report(query_id)
      
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Ibkr::Models::FlexTransaction)
      expect(result.first.symbol).to eq("AAPL")
      expect(result.first.quantity).to eq(100)
    end
    
    it "returns empty array when no transactions" do
      expect(flex_client).to receive(:generate_and_fetch).and_return({})
      
      result = flex_service.transactions_report(query_id)
      expect(result).to eq([])
    end
  end

  describe "#positions_report" do
    let(:position_data) do
      {
        positions: [
          {
            account_id: "DU123456",
            symbol: "AAPL",
            position: 100,
            market_price: 155.00,
            market_value: 15500,
            average_cost: 150.50,
            unrealized_pnl: 450.00,
            realized_pnl: 0,
            currency: "USD",
            asset_class: "STK"
          }
        ]
      }
    end
    
    it "returns FlexPosition models" do
      expect(flex_client).to receive(:generate_and_fetch).with(query_id, max_wait: 60, poll_interval: 5).and_return(position_data)
      
      result = flex_service.positions_report(query_id)
      
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Ibkr::Models::FlexPosition)
      expect(result.first.symbol).to eq("AAPL")
      expect(result.first.unrealized_pnl).to eq(450.00)
    end
    
    it "returns empty array when no positions" do
      expect(flex_client).to receive(:generate_and_fetch).and_return({})
      
      result = flex_service.positions_report(query_id)
      expect(result).to eq([])
    end
  end

  describe "#cash_report" do
    let(:cash_data) do
      {
        cash_report: [
          {
            account_id: "DU123456",
            currency: "USD",
            starting_cash: 100000,
            ending_cash: 105000,
            deposits: 0,
            withdrawals: 0,
            fees: -50,
            dividends: 200,
            interest: 10,
            realized_pnl: 4840
          }
        ]
      }
    end
    
    it "returns FlexCashReport model" do
      expect(flex_client).to receive(:generate_and_fetch).with(query_id, max_wait: 60, poll_interval: 5).and_return(cash_data)
      
      result = flex_service.cash_report(query_id)
      
      expect(result).to be_a(Ibkr::Models::FlexCashReport)
      expect(result.ending_cash).to eq(105000)
      expect(result.net_change).to eq(5000)
    end
    
    it "returns nil when no cash report" do
      expect(flex_client).to receive(:generate_and_fetch).and_return({})
      
      result = flex_service.cash_report(query_id)
      expect(result).to be_nil
    end
  end

  describe "#performance_report" do
    let(:performance_data) do
      {
        performance: [
          {
            account_id: "DU123456",
            period: "YTD",
            nav_start: 100000,
            nav_end: 110000,
            deposits: 0,
            withdrawals: 0,
            realized_pnl: 5000,
            unrealized_pnl: 3000,
            dividends: 1500,
            interest: 100,
            commissions: -600
          }
        ]
      }
    end
    
    it "returns FlexPerformance model" do
      expect(flex_client).to receive(:generate_and_fetch).with(query_id, max_wait: 60, poll_interval: 5).and_return(performance_data)
      
      result = flex_service.performance_report(query_id)
      
      expect(result).to be_a(Ibkr::Models::FlexPerformance)
      expect(result.total_pnl).to eq(8000)
      expect(result.return_percentage).to eq(10.0)
    end
    
    it "returns nil when no performance report" do
      expect(flex_client).to receive(:generate_and_fetch).and_return({})
      
      result = flex_service.performance_report(query_id)
      expect(result).to be_nil
    end
  end

  describe "#available?" do
    context "when token is configured" do
      it "returns true" do
        allow(flex_client).to receive(:token).and_return("configured_token")
        expect(flex_service.available?).to be true
      end
    end
    
    context "when token is not configured" do
      it "returns false" do
        allow(flex_client).to receive(:token).and_return(nil)
        expect(flex_service.available?).to be false
      end
    end
    
    context "when error occurs checking token" do
      it "returns false" do
        allow(flex_client).to receive(:token).and_raise(StandardError)
        expect(flex_service.available?).to be false
      end
    end
  end

  describe "integration with client" do
    let(:real_client) { Ibkr::Client.new(live: false) }
    let(:real_config) { real_client.config }
    
    before do
      allow(real_config).to receive(:flex_token).and_return("test_token")
    end
    
    it "is accessible through client.flex" do
      flex_service = real_client.flex
      expect(flex_service).to be_a(described_class)
    end
    
    it "memoizes the flex service instance" do
      service1 = real_client.flex
      service2 = real_client.flex
      expect(service1).to be(service2)
    end
  end
end