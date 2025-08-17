# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Accounts::Position do
  describe "position data validation and transformation" do
    let(:valid_position_data) do
      {
        conid: "265598",
        position: 100,
        average_cost: 150.25,
        average_price: 148.50,
        currency: "USD",
        description: "APPLE INC",
        unrealized_pnl: 1250.50,
        realized_pnl: 500.00,
        market_value: 16275.00,
        market_price: 162.75,
        security_type: "STK",
        asset_class: "STOCK",
        sector: "Technology",
        group: "Technology - Services"
      }
    end

    context "when creating with valid position data" do
      it "creates a valid Position instance with all trading metrics" do
        # Given valid position data from IBKR portfolio API
        # When creating a Position instance
        position = described_class.new(valid_position_data)

        # Then it should contain all position details
        expect(position.conid).to eq("265598")
        expect(position.position).to eq(100)
        expect(position.description).to eq("APPLE INC")
        expect(position.unrealized_pnl).to eq(1250.50)
        expect(position.market_value).to eq(16275.00)
      end

      it "provides comprehensive position analysis data" do
        position = described_class.new(valid_position_data)

        # Financial metrics should be properly typed
        expect(position.average_cost).to be_a(Numeric)
        expect(position.market_price).to be_a(Numeric)
        expect(position.unrealized_pnl).to be_a(Numeric)
        expect(position.realized_pnl).to be_a(Numeric)

        # Identifiers and descriptions should be strings
        expect(position.conid).to be_a(String)
        expect(position.currency).to be_a(String)
        expect(position.description).to be_a(String)
      end

      include_examples "a data transformation operation", [
        :conid, :position, :average_cost, :market_value, :unrealized_pnl,
        :description, :currency, :security_type
      ] do
        subject { described_class.new(valid_position_data) }
      end
    end

    context "when handling different security types" do
      it "handles stock positions correctly" do
        stock_position = valid_position_data.merge(
          security_type: "STK",
          asset_class: "STOCK"
        )

        position = described_class.new(stock_position)
        expect(position.security_type).to eq("STK")
        expect(position.asset_class).to eq("STOCK")
      end

      it "handles option positions with different characteristics" do
        option_data = valid_position_data.merge(
          conid: "456789012",
          security_type: "OPT",
          asset_class: "OPTION",
          description: "AAPL  240816C00160000",
          position: 5,  # 5 contracts
          market_value: 2500.00
        )

        position = described_class.new(option_data)
        expect(position.security_type).to eq("OPT")
        expect(position.asset_class).to eq("OPTION")
        expect(position.description).to include("AAPL")
        expect(position.position).to eq(5)
      end

      it "handles forex positions" do
        forex_data = valid_position_data.merge(
          conid: "EUR",
          security_type: "CASH",
          asset_class: "CURRENCY",
          description: "EUR.USD",
          currency: "EUR",
          position: 10000.00
        )

        position = described_class.new(forex_data)
        expect(position.security_type).to eq("CASH")
        expect(position.asset_class).to eq("CURRENCY")
        expect(position.currency).to eq("EUR")
      end
    end

    context "when handling numeric type coercion" do
      let(:string_numeric_data) do
        valid_position_data.merge(
          position: "100",           # String integer
          average_cost: "150.25",    # String float
          market_price: "162.75",    # String float
          unrealized_pnl: "1250.50" # String float
        )
      end

      it "coerces string numbers to proper numeric types" do
        position = described_class.new(string_numeric_data)

        expect(position.position).to eq(100)
        expect(position.position).to be_a(Integer)
        expect(position.average_cost).to eq(150.25)
        expect(position.average_cost).to be_a(Float)
        expect(position.market_price).to eq(162.75)
        expect(position.unrealized_pnl).to eq(1250.50)
      end

      it "handles negative positions (short positions)" do
        short_position_data = valid_position_data.merge(
          position: -50,
          unrealized_pnl: -750.25,
          market_value: -8137.50
        )

        position = described_class.new(short_position_data)
        expect(position.position).to eq(-50)
        expect(position.unrealized_pnl).to eq(-750.25)
        expect(position.market_value).to eq(-8137.50)
      end
    end

    context "when handling optional attributes" do
      let(:minimal_position_data) do
        {
          conid: "265598",
          position: 100,
          currency: "USD",
          description: "APPLE INC",
          unrealized_pnl: 1250.50,
          realized_pnl: 0.00,
          market_value: 16275.00,
          market_price: 162.75,
          security_type: "STK",
          asset_class: "STOCK",
          sector: "Technology",
          group: "Technology - Services"
        }
      end

      it "handles missing optional cost data" do
        position = described_class.new(minimal_position_data)

        expect(position.conid).to eq("265598")
        expect(position.position).to eq(100)
        expect(position.market_value).to eq(16275.00)
        # average_cost and average_price should provide sensible defaults when data is missing
        expect(position.average_cost).to be_nil.or be_a(Numeric)
        expect(position.average_price).to be_nil.or be_a(Numeric)
      end
    end

    context "when calculating position metrics" do
      it "provides data for profit/loss calculations" do
        position = described_class.new(valid_position_data)

        # Should have all components for P&L analysis
        expect(position.unrealized_pnl).to be > 0  # Profitable position
        expect(position.market_value).to be > (position.average_cost * position.position)
        expect(position.market_price).to be > position.average_cost
      end

      it "handles losing positions appropriately" do
        losing_position_data = valid_position_data.merge(
          market_price: 140.00,
          market_value: 14000.00,
          unrealized_pnl: -1025.00
        )

        position = described_class.new(losing_position_data)
        expect(position.unrealized_pnl).to be < 0
        expect(position.market_price).to be < position.average_cost
      end
    end
  end

  describe "validation failures" do
    context "when required attributes are missing" do
      it "raises error for missing contract ID" do
        invalid_data = valid_position_data.except(:conid)

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "raises error for missing position size" do
        invalid_data = valid_position_data.except(:position)

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      %i[currency description unrealized_pnl realized_pnl market_value
        market_price security_type asset_class sector group].each do |required_field|
        it "raises error for missing #{required_field}" do
          invalid_data = valid_position_data.except(required_field)

          expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
        end
      end
    end

    context "when attributes have wrong types" do
      it "raises error for non-numeric position" do
        invalid_data = valid_position_data.merge(position: "not_a_number")

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "raises error for non-string description" do
        invalid_data = valid_position_data.merge(description: 123456)

        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end
    end
  end

  describe "real-world position scenarios" do
    it "handles typical equity position from IBKR API" do
      equity_position = {
        conid: "76792991",
        position: 200,
        average_cost: 95.50,
        average_price: 94.75,
        currency: "USD",
        description: "MICROSOFT CORP",
        unrealized_pnl: 2100.00,
        realized_pnl: 150.00,
        market_value: 21200.00,
        market_price: 106.00,
        security_type: "STK",
        asset_class: "STOCK",
        sector: "Technology",
        group: "Technology - Software"
      }

      position = described_class.new(equity_position)

      expect(position.description).to eq("MICROSOFT CORP")
      expect(position.position).to eq(200)
      expect(position.unrealized_pnl).to be > 0
      expect(position.market_value).to eq(position.market_price * position.position)
    end

    it "handles international stock position with currency conversion" do
      international_position = {
        conid: "11005391",
        position: 500,
        average_cost: 45.30,
        average_price: 44.85,
        currency: "EUR",
        description: "ASML HOLDING NV-NY REG SHS",
        unrealized_pnl: 1250.00,
        realized_pnl: 0.00,
        market_value: 24500.00,
        market_price: 49.00,
        security_type: "STK",
        asset_class: "STOCK",
        sector: "Technology",
        group: "Technology - Semiconductors"
      }

      position = described_class.new(international_position)

      expect(position.currency).to eq("EUR")
      expect(position.description).to include("ASML")
      expect(position.position).to eq(500)
    end

    it "handles zero position (recently closed)" do
      closed_position = valid_position_data.merge(
        position: 0,
        market_value: 0.00,
        unrealized_pnl: 0.00,
        realized_pnl: 275.50  # Only realized P&L remains
      )

      position = described_class.new(closed_position)

      expect(position.position).to eq(0)
      expect(position.market_value).to eq(0.00)
      expect(position.unrealized_pnl).to eq(0.00)
      expect(position.realized_pnl).to be > 0
    end
  end

  private

  let(:valid_position_data) do
    {
      conid: "265598",
      position: 100,
      average_cost: 150.25,
      average_price: 148.50,
      currency: "USD",
      description: "APPLE INC",
      unrealized_pnl: 1250.50,
      realized_pnl: 500.00,
      market_value: 16275.00,
      market_price: 162.75,
      security_type: "STK",
      asset_class: "STOCK",
      sector: "Technology",
      group: "Technology - Services"
    }
  end
end
