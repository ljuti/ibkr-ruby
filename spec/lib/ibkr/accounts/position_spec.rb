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

  describe "position type classification" do
    context "when position is long" do
      it "correctly identifies long positions" do
        # Given a position with positive shares
        long_position_data = valid_position_data.merge(position: 100)
        position = described_class.new(long_position_data)

        # When checking position type
        # Then it should identify as long position
        expect(position.long?).to be(true)
        expect(position.short?).to be(false)
        expect(position.flat?).to be(false)
      end
    end

    context "when position is short" do
      it "correctly identifies short positions" do
        # Given a position with negative shares
        short_position_data = valid_position_data.merge(position: -50)
        position = described_class.new(short_position_data)

        # When checking position type
        # Then it should identify as short position
        expect(position.short?).to be(true)
        expect(position.long?).to be(false)
        expect(position.flat?).to be(false)
      end
    end

    context "when position is flat" do
      it "correctly identifies flat positions" do
        # Given a position with zero shares
        flat_position_data = valid_position_data.merge(position: 0)
        position = described_class.new(flat_position_data)

        # When checking position type
        # Then it should identify as flat position
        expect(position.flat?).to be(true)
        expect(position.long?).to be(false)
        expect(position.short?).to be(false)
      end
    end
  end

  describe "P&L calculations" do
    context "when calculating total P&L" do
      it "combines unrealized and realized P&L" do
        # Given a position with both unrealized and realized P&L
        pnl_data = valid_position_data.merge(
          unrealized_pnl: 1500.00,
          realized_pnl: 250.00
        )
        position = described_class.new(pnl_data)

        # When calculating total P&L
        # Then it should sum both components
        expect(position.total_pnl).to eq(1750.00)
      end

      it "handles negative P&L values correctly" do
        # Given a position with negative P&L
        loss_data = valid_position_data.merge(
          unrealized_pnl: -500.00,
          realized_pnl: -250.00
        )
        position = described_class.new(loss_data)

        # When calculating total P&L
        # Then it should sum negative values correctly
        expect(position.total_pnl).to eq(-750.00)
      end
    end

    context "when calculating P&L percentage" do
      it "calculates percentage for long positions" do
        # Given a profitable long position
        pnl_data = valid_position_data.merge(
          position: 100,
          average_cost: 150.00,
          unrealized_pnl: 1500.00
        )
        position = described_class.new(pnl_data)

        # When calculating P&L percentage
        # Then it should calculate based on cost basis
        cost_basis = 150.00 * 100
        expected_percentage = (1500.00 / cost_basis * 100).round(2)
        expect(position.pnl_percentage).to eq(expected_percentage)
        expect(position.pnl_percentage).to eq(10.0)
      end

      it "calculates percentage for short positions" do
        # Given a profitable short position
        pnl_data = valid_position_data.merge(
          position: -50,
          average_cost: 200.00,
          unrealized_pnl: 1000.00
        )
        position = described_class.new(pnl_data)

        # When calculating P&L percentage
        # Then it should use absolute position for cost basis
        cost_basis = 200.00 * 50  # Use absolute value
        expected_percentage = (1000.00 / cost_basis * 100).round(2)
        expect(position.pnl_percentage).to eq(expected_percentage)
        expect(position.pnl_percentage).to eq(10.0)
      end

      it "returns nil when required data is missing" do
        # Given a position without average cost
        incomplete_data = valid_position_data.merge(
          average_cost: nil,
          unrealized_pnl: 1500.00
        )
        position = described_class.new(incomplete_data)

        # When calculating P&L percentage
        # Then it should return nil
        expect(position.pnl_percentage).to be_nil
      end

      it "returns nil for flat positions" do
        # Given a flat position
        flat_data = valid_position_data.merge(
          position: 0,
          average_cost: 150.00,
          unrealized_pnl: 0.00
        )
        position = described_class.new(flat_data)

        # When calculating P&L percentage
        # Then it should return nil
        expect(position.pnl_percentage).to be_nil
      end

      it "returns nil when cost basis is zero" do
        # Given a position with zero average cost
        zero_cost_data = valid_position_data.merge(
          position: 100,
          average_cost: 0.00,
          unrealized_pnl: 1500.00
        )
        position = described_class.new(zero_cost_data)

        # When calculating P&L percentage
        # Then it should return nil to avoid division by zero
        expect(position.pnl_percentage).to be_nil
      end
    end
  end

  describe "position value calculations" do
    context "when calculating notional value" do
      it "calculates notional value for long positions" do
        # Given a long position
        position_data = valid_position_data.merge(
          position: 100,
          market_price: 162.75
        )
        position = described_class.new(position_data)

        # When calculating notional value
        # Then it should multiply market price by absolute position
        expect(position.notional_value).to eq(16275.00)
      end

      it "calculates notional value for short positions" do
        # Given a short position
        position_data = valid_position_data.merge(
          position: -50,
          market_price: 162.75
        )
        position = described_class.new(position_data)

        # When calculating notional value
        # Then it should use absolute position value
        expect(position.notional_value).to eq(8137.50)
      end

      it "calculates notional value for zero positions" do
        # Given a flat position (zero shares)
        zero_position_data = valid_position_data.merge(
          position: 0,
          market_price: 162.75
        )
        position = described_class.new(zero_position_data)

        # When calculating notional value
        # Then it should be zero
        expect(position.notional_value).to eq(0.0)
      end
    end

    context "when calculating cost basis" do
      it "calculates cost basis for long positions" do
        # Given a long position
        position_data = valid_position_data.merge(
          position: 100,
          average_cost: 150.25
        )
        position = described_class.new(position_data)

        # When calculating cost basis
        # Then it should multiply average cost by absolute position
        expect(position.cost_basis).to eq(15025.00)
      end

      it "calculates cost basis for short positions" do
        # Given a short position
        position_data = valid_position_data.merge(
          position: -75,
          average_cost: 200.00
        )
        position = described_class.new(position_data)

        # When calculating cost basis
        # Then it should use absolute position value
        expect(position.cost_basis).to eq(15000.00)
      end

      it "returns nil when average cost is missing" do
        # Given a position without average cost
        incomplete_data = valid_position_data.merge(average_cost: nil)
        position = described_class.new(incomplete_data)

        # When calculating cost basis
        # Then it should return nil
        expect(position.cost_basis).to be_nil
      end
    end
  end

  describe "risk metrics" do
    context "when calculating exposure percentage" do
      it "calculates position exposure relative to account size" do
        # Given a position and account net liquidation value
        position_data = valid_position_data.merge(market_value: 16275.00)
        position = described_class.new(position_data)
        account_net_liquidation = 100000.00

        # When calculating exposure percentage
        exposure = position.exposure_percentage(account_net_liquidation)

        # Then it should calculate percentage of account exposure
        expected_percentage = (16275.00 / 100000.00 * 100).round(2)
        expect(exposure).to eq(expected_percentage)
        expect(exposure).to eq(16.28)
      end

      it "uses absolute market value for short positions" do
        # Given a short position with negative market value
        position_data = valid_position_data.merge(market_value: -8137.50)
        position = described_class.new(position_data)
        account_net_liquidation = 50000.00

        # When calculating exposure percentage
        exposure = position.exposure_percentage(account_net_liquidation)

        # Then it should use absolute market value
        expected_percentage = (8137.50 / 50000.00 * 100).round(2)
        expect(exposure).to eq(expected_percentage)
        expect(exposure).to eq(16.28)
      end

      it "handles very small positions relative to account size" do
        # Given a very small position
        small_position_data = valid_position_data.merge(market_value: 100.00)
        position = described_class.new(small_position_data)
        large_account = 1000000.00

        # When calculating exposure percentage
        exposure = position.exposure_percentage(large_account)

        # Then it should calculate very small percentage
        expect(exposure).to eq(0.01) # 100/1000000 * 100
      end

      it "returns nil when account net liquidation is zero or negative" do
        # Given a position with valid market value
        position = described_class.new(valid_position_data)

        # When calculating exposure with invalid account value
        # Then it should return nil
        expect(position.exposure_percentage(0.00)).to be_nil
        expect(position.exposure_percentage(-10000.00)).to be_nil
      end
    end
  end

  describe "display helpers" do
    context "when formatting position size" do
      it "formats integer positions without decimal places" do
        # Given a position with integer size
        position_data = valid_position_data.merge(position: 100)
        position = described_class.new(position_data)

        # When formatting position
        # Then it should display as integer
        expect(position.formatted_position).to eq("100")
      end

      it "formats fractional positions with decimal places" do
        # Given a position with fractional size
        position_data = valid_position_data.merge(position: 100.5)
        position = described_class.new(position_data)

        # When formatting position
        # Then it should preserve decimal places
        expect(position.formatted_position).to eq("100.5")
      end

      it "handles negative positions" do
        # Given a short position
        position_data = valid_position_data.merge(position: -50)
        position = described_class.new(position_data)

        # When formatting position
        # Then it should preserve negative sign
        expect(position.formatted_position).to eq("-50")
      end
    end

    context "when creating position summary" do
      it "creates summary for long positions" do
        # Given a long position
        position_data = valid_position_data.merge(
          position: 100,
          description: "APPLE INC"
        )
        position = described_class.new(position_data)

        # When creating position summary
        # Then it should indicate long direction
        expect(position.position_summary).to eq("LONG 100 APPLE INC")
      end

      it "creates summary for short positions" do
        # Given a short position
        position_data = valid_position_data.merge(
          position: -50,
          description: "TESLA INC"
        )
        position = described_class.new(position_data)

        # When creating position summary
        # Then it should indicate short direction
        expect(position.position_summary).to eq("SHORT -50 TESLA INC")
      end

      it "creates summary for flat positions" do
        # Given a flat position
        position_data = valid_position_data.merge(
          position: 0,
          description: "MICROSOFT CORP"
        )
        position = described_class.new(position_data)

        # When creating position summary
        # Then it should indicate flat direction
        expect(position.position_summary).to eq("FLAT 0 MICROSOFT CORP")
      end
    end
  end

  describe "attention and alert logic" do
    context "when checking if position needs attention" do
      it "identifies positions with significant losses using default threshold" do
        # Given a position with large unrealized loss
        losing_position = valid_position_data.merge(
          position: 100,
          average_cost: 150.00,
          unrealized_pnl: -1500.00  # -10% loss
        )
        position = described_class.new(losing_position)

        # When checking if attention is needed
        # Then it should flag position for attention
        expect(position.attention_needed?).to be(true)
      end

      it "identifies positions with minor losses as not needing attention" do
        # Given a position with small unrealized loss
        minor_loss_position = valid_position_data.merge(
          position: 100,
          average_cost: 150.00,
          unrealized_pnl: -750.00  # -5% loss
        )
        position = described_class.new(minor_loss_position)

        # When checking if attention is needed
        # Then it should not flag position for attention
        expect(position.attention_needed?).to be(false)
      end

      it "allows custom threshold for attention alerts" do
        # Given a position with moderate loss
        position_data = valid_position_data.merge(
          position: 100,
          average_cost: 150.00,
          unrealized_pnl: -900.00  # -6% loss
        )
        position = described_class.new(position_data)

        # When checking with custom threshold
        # Then it should respect custom threshold
        expect(position.attention_needed?(-5.0)).to be(true)  # 6% > 5% threshold
        expect(position.attention_needed?(-7.0)).to be(false) # 6% < 7% threshold
      end

      it "does not flag profitable positions for attention" do
        # Given a profitable position
        profitable_position = valid_position_data.merge(
          position: 100,
          average_cost: 150.00,
          unrealized_pnl: 1500.00  # +10% gain
        )
        position = described_class.new(profitable_position)

        # When checking if attention is needed
        # Then it should not flag profitable position
        expect(position.attention_needed?).to be(false)
      end

      it "returns false when P&L percentage cannot be calculated" do
        # Given a position without sufficient data for P&L calculation
        incomplete_position = valid_position_data.merge(average_cost: nil)
        position = described_class.new(incomplete_position)

        # When checking if attention is needed
        # Then it should return false
        expect(position.attention_needed?).to be(false)
      end
    end
  end

  describe "summary hash for reporting" do
    it "creates compact summary hash with key position data" do
      # Given a position
      position_data = valid_position_data.merge(
        position: 100,
        description: "APPLE INC",
        market_value: 16275.00,
        unrealized_pnl: 1250.50
      )
      position = described_class.new(position_data)

      # When creating summary hash
      summary = position.summary_hash

      # Then it should include key position information
      expect(summary).to include(
        symbol: "APPLE INC",
        position: "100",
        market_value: 16275.00,
        unrealized_pnl: 1250.50,
        direction: "LONG"
      )
      expect(summary[:pnl_percentage]).to be_a(Numeric)
    end

    it "creates summary for short positions" do
      # Given a short position
      short_position_data = valid_position_data.merge(
        position: -50,
        description: "SHORT STOCK"
      )
      position = described_class.new(short_position_data)

      # When creating summary hash
      summary = position.summary_hash

      # Then it should indicate short direction
      expect(summary[:direction]).to eq("SHORT")
      expect(summary[:position]).to eq("-50")
    end

    it "creates summary for flat positions" do
      # Given a flat position
      flat_position_data = valid_position_data.merge(
        position: 0,
        description: "CLOSED POSITION"
      )
      position = described_class.new(flat_position_data)

      # When creating summary hash
      summary = position.summary_hash

      # Then it should indicate flat direction
      expect(summary[:direction]).to eq("FLAT")
      expect(summary[:position]).to eq("0")
    end

    it "compacts summary by removing nil values" do
      # Given a position with missing optional data
      minimal_position = valid_position_data.merge(
        average_cost: nil,
        unrealized_pnl: 1250.50
      )
      position = described_class.new(minimal_position)

      # When creating summary hash
      summary = position.summary_hash

      # Then it should remove nil values
      expect(summary).not_to have_key(:pnl_percentage) # nil because no average_cost
      expect(summary).to include(:unrealized_pnl)       # present
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
      expect(position.long?).to be(true)
      expect(position.unrealized_pnl).to be > 0
      expect(position.market_value).to eq(position.market_price * position.position)
      expect(position.total_pnl).to eq(2250.00)
      expect(position.attention_needed?).to be(false)
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
      expect(position.long?).to be(true)
      expect(position.cost_basis).to eq(22650.00) # 500 * 45.30
      expect(position.notional_value).to eq(24500.00) # 500 * 49.00
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
      expect(position.flat?).to be(true)
      expect(position.market_value).to eq(0.00)
      expect(position.unrealized_pnl).to eq(0.00)
      expect(position.realized_pnl).to be > 0
      expect(position.total_pnl).to eq(275.50)
      expect(position.position_summary).to include("FLAT")
    end

    it "handles fractional share positions" do
      fractional_position = valid_position_data.merge(
        position: 10.5,
        average_cost: 150.00,
        market_price: 160.00,
        market_value: 1680.00,
        unrealized_pnl: 105.00
      )

      position = described_class.new(fractional_position)

      expect(position.position).to eq(10.5)
      expect(position.long?).to be(true)
      expect(position.formatted_position).to eq("10.5")
      expect(position.cost_basis).to eq(1575.00) # 10.5 * 150.00
      expect(position.notional_value).to eq(1680.00) # 10.5 * 160.00
    end

    it "handles large short position with significant unrealized loss" do
      large_short_position = valid_position_data.merge(
        position: -1000,
        average_cost: 50.00,
        market_price: 55.00,
        market_value: -55000.00,
        unrealized_pnl: -5000.00,
        description: "SHORTED STOCK"
      )

      position = described_class.new(large_short_position)

      expect(position.short?).to be(true)
      expect(position.position_summary).to eq("SHORT -1000 SHORTED STOCK")
      expect(position.attention_needed?).to be(true) # -10% loss
      expect(position.cost_basis).to eq(50000.00) # 1000 * 50.00
      expect(position.exposure_percentage(500000.00)).to eq(11.0) # 55000/500000 * 100
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
