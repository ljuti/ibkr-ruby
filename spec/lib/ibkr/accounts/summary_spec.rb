# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Accounts::Summary do
  describe "data structure validation" do
    let(:valid_account_value) do
      {
        value: 50000.00,
        currency: "USD",
        amount: 50000.00,
        timestamp: Time.now
      }
    end

    let(:valid_summary_data) do
      {
        account_id: "DU123456",
        accrued_cash: valid_account_value,
        available_funds: valid_account_value,
        buying_power: valid_account_value.merge(amount: 100000.00),
        cushion: valid_account_value.merge(value: 0.85),
        equity_with_loan: valid_account_value,
        excess_liquidity: valid_account_value.merge(amount: 25000.00),
        gross_position_value: valid_account_value.merge(amount: 75000.00),
        initial_margin: valid_account_value.merge(amount: 15000.00),
        maintenance_margin: valid_account_value.merge(amount: 12000.00),
        net_liquidation_value: valid_account_value,
        total_cash_value: valid_account_value.merge(amount: 25000.00)
      }
    end

    context "when creating with valid data" do
      it "creates a valid Summary instance with all required attributes" do
        # Given valid portfolio summary data from IBKR API
        # When creating a Summary instance
        summary = described_class.new(valid_summary_data)

        # Then it should contain all portfolio metrics
        expect(summary.account_id).to eq("DU123456")
        expect(summary.net_liquidation_value).to be_instance_of(Ibkr::Accounts::AccountValue)
        expect(summary.buying_power.amount).to eq(100000.00)
        expect(summary.available_funds.currency).to eq("USD")
      end

      it "properly transforms and validates account values" do
        summary = described_class.new(valid_summary_data)

        # Each financial metric should be an AccountValue instance
        %i[accrued_cash available_funds buying_power cushion equity_with_loan
          excess_liquidity gross_position_value initial_margin maintenance_margin
          net_liquidation_value total_cash_value].each do |attr|
          expect(summary.public_send(attr)).to be_instance_of(Ibkr::Accounts::AccountValue)
        end
      end

      it "transforms all expected attributes" do
        summary = described_class.new(valid_summary_data)
        [
          :account_id, :accrued_cash, :available_funds, :buying_power,
          :net_liquidation_value, :total_cash_value
        ].each do |attr|
          expect(summary).to respond_to(attr)
        end
      end

      it "coerces AccountValue numeric types correctly" do
        summary = described_class.new(valid_summary_data)
        # Check that AccountValue objects have numeric amounts/values
        expect(summary.net_liquidation_value.amount).to be_a(Numeric)
        expect(summary.available_funds.amount).to be_a(Numeric)
        expect(summary.buying_power.amount).to be_a(Numeric)
      end
    end

    context "when creating with coercible data types" do
      let(:string_numeric_data) do
        valid_summary_data.transform_values(&:dup).tap do |data|
          data[:buying_power][:amount] = "100000.50"  # String that should coerce to float
          data[:cushion][:value] = "0.85"  # String percentage
        end
      end

      it "coerces string numbers to proper numeric types" do
        summary = described_class.new(string_numeric_data)

        expect(summary.buying_power.amount).to eq(100000.50)
        expect(summary.buying_power.amount).to be_a(Float)
        expect(summary.cushion.value).to eq(0.85)
      end

      it "handles integer values in amount fields" do
        integer_data = valid_summary_data.transform_values(&:dup)
        integer_data[:available_funds][:amount] = 25000  # Integer

        summary = described_class.new(integer_data)
        expect(summary.available_funds.amount).to eq(25000)
        expect([Integer, Float]).to include(summary.available_funds.amount.class)
      end
    end

    context "when creating with missing optional values" do
      let(:minimal_data) do
        {
          account_id: "DU123456",
          accrued_cash: {value: nil, currency: nil, amount: nil, timestamp: nil},
          available_funds: {value: 25000.00},
          buying_power: {amount: 50000.00, currency: "USD"},
          cushion: {},
          equity_with_loan: {value: 50000.00},
          excess_liquidity: {amount: 10000.00},
          gross_position_value: {amount: 60000.00},
          initial_margin: {amount: 5000.00},
          maintenance_margin: {amount: 4000.00},
          net_liquidation_value: {value: 50000.00, currency: "USD"},
          total_cash_value: {amount: 20000.00}
        }
      end

      it "handles missing optional AccountValue attributes gracefully" do
        summary = described_class.new(minimal_data)

        expect(summary.accrued_cash.value).to be_nil
        expect(summary.accrued_cash.currency).to be_nil
        expect(summary.cushion.amount).to be_nil  # Default from Dry::Struct
        expect(summary.available_funds.value).to eq(25000.00)
      end
    end

    context "when handling key transformation" do
      let(:ibkr_api_response) do
        {
          :account_id => "DU123456",
          "netliquidation" => {"amount" => 50000.00, "currency" => "USD"},
          "availablefunds" => {"amount" => 25000.00, "currency" => "USD"},
          "buyingpower" => {"amount" => 100000.00, "currency" => "USD"},
          "accruedcash" => {"amount" => 150.00, "currency" => "USD"},
          "cushion" => {"value" => 0.89},
          "equitywithloanvalue" => {"amount" => 50000.00, "currency" => "USD"},
          "excessliquidity" => {"amount" => 30000.00, "currency" => "USD"},
          "grosspositionvalue" => {"amount" => 75000.00, "currency" => "USD"},
          "initmarginreq" => {"amount" => 15000.00, "currency" => "USD"},
          "maintmarginreq" => {"amount" => 12000.00, "currency" => "USD"},
          "totalcashvalue" => {"amount" => 25000.00, "currency" => "USD"}
        }
      end

      it "should work with the key mapping from IBKR API format" do
        # Note: This test shows the expected transformation that would happen
        # in the Accounts#normalize_summary method before creating the Summary

        # The KEY_MAPPING constant should handle the transformation
        expect(described_class::KEY_MAPPING).to include(
          "netliquidation" => "net_liquidation_value",
          "availablefunds" => "available_funds",
          "buyingpower" => "buying_power"
        )
      end
    end
  end

  describe "validation failures" do
    context "when required attributes are missing" do
      it "raises error for missing account_id" do
        invalid_data = valid_summary_data.except(:account_id)

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "raises error for missing required AccountValue fields" do
        invalid_data = valid_summary_data.except(:net_liquidation_value)

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end
    end

    context "when attributes have wrong types" do
      it "raises error for non-string account_id" do
        invalid_data = valid_summary_data.merge(account_id: 123456)

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "raises error for invalid AccountValue structure" do
        invalid_data = valid_summary_data.merge(buying_power: "not_a_hash")

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end
    end
  end

  describe "real-world usage scenarios" do
    it "handles typical IBKR portfolio summary response structure" do
      # Given a realistic response from IBKR portfolio summary API
      realistic_data = {
        account_id: "DU987654321",
        accrued_cash: {amount: 45.67, currency: "USD", timestamp: Time.now},
        available_funds: {amount: 75432.10, currency: "USD", timestamp: Time.now},
        buying_power: {amount: 150864.20, currency: "USD", timestamp: Time.now},
        cushion: {value: 0.7532},
        equity_with_loan: {amount: 98765.43, currency: "USD", timestamp: Time.now},
        excess_liquidity: {amount: 45123.87, currency: "USD", timestamp: Time.now},
        gross_position_value: {amount: 123456.78, currency: "USD", timestamp: Time.now},
        initial_margin: {amount: 23456.78, currency: "USD", timestamp: Time.now},
        maintenance_margin: {amount: 18765.43, currency: "USD", timestamp: Time.now},
        net_liquidation_value: {amount: 98765.43, currency: "USD", timestamp: Time.now},
        total_cash_value: {amount: 15432.10, currency: "USD", timestamp: Time.now}
      }

      # When creating a Summary from this data
      summary = described_class.new(realistic_data)

      # Then it should provide meaningful financial insights
      expect(summary.buying_power.amount).to be > summary.available_funds.amount
      expect(summary.net_liquidation_value.amount).to be > 0
      expect(summary.cushion.value).to be_between(0, 1)
      expect(summary.account_id).to match(/^DU\d+$/)
    end

    it "supports multi-currency account scenarios" do
      multi_currency_data = valid_summary_data.transform_values(&:dup)
      multi_currency_data[:available_funds][:currency] = "EUR"
      multi_currency_data[:buying_power][:currency] = "EUR"

      summary = described_class.new(multi_currency_data)

      expect(summary.available_funds.currency).to eq("EUR")
      expect(summary.buying_power.currency).to eq("EUR")
      expect(summary.net_liquidation_value.currency).to eq("USD")  # Base currency
    end
  end

  private

  let(:valid_summary_data) do
    {
      account_id: "DU123456",
      accrued_cash: valid_account_value,
      available_funds: valid_account_value,
      buying_power: valid_account_value.merge(amount: 100000.00),
      cushion: valid_account_value.merge(value: 0.85),
      equity_with_loan: valid_account_value,
      excess_liquidity: valid_account_value.merge(amount: 25000.00),
      gross_position_value: valid_account_value.merge(amount: 75000.00),
      initial_margin: valid_account_value.merge(amount: 15000.00),
      maintenance_margin: valid_account_value.merge(amount: 12000.00),
      net_liquidation_value: valid_account_value,
      total_cash_value: valid_account_value.merge(amount: 25000.00)
    }
  end

  let(:valid_account_value) do
    {
      value: 50000.00,
      currency: "USD",
      amount: 50000.00,
      timestamp: Time.now
    }
  end
end
