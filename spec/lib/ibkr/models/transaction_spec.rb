# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Models::Transaction do
  describe "transaction data validation and transformation" do
    let(:valid_transaction_data) do
      {
        date: "2024-01-15T10:30:00",
        cur: "USD",
        pr: 150.25,
        qty: 100,
        amt: 15025.00,
        conid: 265598,
        desc: "APPLE INC",
        type: "BUY"
      }
    end

    context "when creating with valid transaction data" do
      it "creates a valid Transaction instance with all trading details" do
        # Given valid transaction data from IBKR API
        # When creating a Transaction instance
        transaction = described_class.new(valid_transaction_data)

        # Then it should contain all transaction details
        expect(transaction.date).to eq("2024-01-15T10:30:00")
        expect(transaction.cur).to eq("USD")
        expect(transaction.pr).to eq(150.25)
        expect(transaction.qty).to eq(100)
        expect(transaction.amt).to eq(15025.00)
        expect(transaction.conid).to eq(265598)
        expect(transaction.desc).to eq("APPLE INC")
        expect(transaction.type).to eq("BUY")
      end

      it "provides convenient attribute aliases" do
        # Given a transaction instance
        transaction = described_class.new(valid_transaction_data)

        # When accessing attributes via aliases
        # Then aliases should map to correct attributes
        expect(transaction.currency).to eq(transaction.cur)
        expect(transaction.price).to eq(transaction.pr)
        expect(transaction.quantity).to eq(transaction.qty)
        expect(transaction.amount).to eq(transaction.amt)
        expect(transaction.contract_id).to eq(transaction.conid)
        expect(transaction.description).to eq(transaction.desc)
        expect(transaction.transaction_type).to eq(transaction.type)
      end

      include_examples "a data transformation operation", [
        :date, :cur, :pr, :qty, :amt, :conid, :desc, :type
      ] do
        subject { described_class.new(valid_transaction_data) }
      end
    end

    context "when handling numeric type coercion" do
      let(:string_numeric_data) do
        valid_transaction_data.merge(
          pr: "150.25",        # String price
          qty: "100",          # String quantity
          amt: "15025.00",     # String amount
          conid: "265598"      # String contract ID
        )
      end

      it "coerces string numbers to proper numeric types" do
        # Given transaction data with string numbers (except conid which requires integer)
        coercible_data = valid_transaction_data.merge(
          pr: "150.25",        # String price
          qty: "100",          # String quantity
          amt: "15025.00",     # String amount
          conid: 265598        # Keep as integer since it doesn't coerce strings
        )

        # When creating transaction
        transaction = described_class.new(coercible_data)

        # Then numeric fields should be properly coerced
        expect(transaction.pr).to eq(150.25)
        expect(transaction.pr).to be_a(Float)
        expect(transaction.qty).to eq(100)
        expect(transaction.qty).to be_a(Numeric)
        expect(transaction.amt).to eq(15025.00)
        expect(transaction.amt).to be_a(Numeric)
        expect(transaction.conid).to eq(265598)
        expect(transaction.conid).to be_a(Integer)
      end
    end
  end

  describe "date and time parsing" do
    context "when parsing transaction dates" do
      it "parses valid ISO 8601 date strings" do
        # Given a transaction with ISO date
        transaction_data = valid_transaction_data.merge(
          date: "2024-03-15T14:30:25"
        )
        transaction = described_class.new(transaction_data)

        # When parsing transaction date
        parsed_date = transaction.transaction_date

        # Then it should parse correctly as Date
        expect(parsed_date).to be_a(Date)
        expect(parsed_date.year).to eq(2024)
        expect(parsed_date.month).to eq(3)
        expect(parsed_date.day).to eq(15)
      end

      it "parses simple date strings" do
        # Given a transaction with simple date format
        transaction_data = valid_transaction_data.merge(
          date: "2024-06-20"
        )
        transaction = described_class.new(transaction_data)

        # When parsing transaction date
        parsed_date = transaction.transaction_date

        # Then it should parse correctly
        expect(parsed_date).to eq(Date.new(2024, 6, 20))
      end

      it "handles invalid date strings gracefully" do
        # Given a transaction with invalid date
        transaction_data = valid_transaction_data.merge(
          date: "invalid-date-string"
        )
        transaction = described_class.new(transaction_data)

        # When parsing transaction date
        parsed_date = transaction.transaction_date

        # Then it should return nil
        expect(parsed_date).to be_nil
      end

      it "caches parsed date for repeated access" do
        # Given a transaction with valid date
        transaction = described_class.new(valid_transaction_data)

        # When accessing date multiple times
        first_access = transaction.transaction_date
        second_access = transaction.transaction_date

        # Then it should return same object (cached)
        expect(first_access).to be(second_access)
      end
    end

    context "when parsing transaction times" do
      it "parses valid timestamp strings to Time objects" do
        # Given a transaction with timestamp
        transaction_data = valid_transaction_data.merge(
          date: "2024-03-15T14:30:25"
        )
        transaction = described_class.new(transaction_data)

        # When parsing transaction time
        parsed_time = transaction.transaction_time

        # Then it should parse correctly as Time
        expect(parsed_time).to be_a(Time)
        expect(parsed_time.hour).to eq(14)
        expect(parsed_time.min).to eq(30)
        expect(parsed_time.sec).to eq(25)
      end

      it "handles invalid time strings gracefully" do
        # Given a transaction with invalid timestamp
        transaction_data = valid_transaction_data.merge(
          date: "not-a-valid-timestamp"
        )
        transaction = described_class.new(transaction_data)

        # When parsing transaction time
        parsed_time = transaction.transaction_time

        # Then it should return nil
        expect(parsed_time).to be_nil
      end

      it "caches parsed time for repeated access" do
        # Given a transaction with valid timestamp
        transaction = described_class.new(valid_transaction_data)

        # When accessing time multiple times
        first_access = transaction.transaction_time
        second_access = transaction.transaction_time

        # Then it should return same object (cached)
        expect(first_access).to be(second_access)
      end
    end
  end

  describe "transaction type classification" do
    context "when identifying buy transactions" do
      it "identifies explicit BUY transaction types" do
        # Given a transaction marked as BUY
        buy_transaction_data = valid_transaction_data.merge(
          type: "BUY",
          qty: 100
        )
        transaction = described_class.new(buy_transaction_data)

        # When checking transaction type
        # Then it should identify as buy
        expect(transaction.buy?).to be(true)
        expect(transaction.sell?).to be(false)
      end

      it "identifies buy transactions by positive quantity" do
        # Given a transaction with positive quantity
        positive_qty_data = valid_transaction_data.merge(
          type: "TRADE",
          qty: 50
        )
        transaction = described_class.new(positive_qty_data)

        # When checking transaction type
        # Then positive quantity indicates buy
        expect(transaction.buy?).to be(true)
        expect(transaction.sell?).to be(false)
      end

      it "handles case-insensitive BUY type identification" do
        # Given a transaction with lowercase buy type
        lowercase_buy_data = valid_transaction_data.merge(
          type: "buy_order",
          qty: 25
        )
        transaction = described_class.new(lowercase_buy_data)

        # When checking transaction type
        # Then it should identify as buy regardless of case
        expect(transaction.buy?).to be(true)
      end
    end

    context "when identifying sell transactions" do
      it "identifies explicit SELL transaction types" do
        # Given a transaction marked as SELL
        sell_transaction_data = valid_transaction_data.merge(
          type: "SELL",
          qty: -100
        )
        transaction = described_class.new(sell_transaction_data)

        # When checking transaction type
        # Then it should identify as sell
        expect(transaction.sell?).to be(true)
        expect(transaction.buy?).to be(false)
      end

      it "identifies sell transactions by negative quantity" do
        # Given a transaction with negative quantity
        negative_qty_data = valid_transaction_data.merge(
          type: "TRADE",
          qty: -75
        )
        transaction = described_class.new(negative_qty_data)

        # When checking transaction type
        # Then negative quantity indicates sell
        expect(transaction.sell?).to be(true)
        expect(transaction.buy?).to be(false)
      end

      it "handles case-insensitive SELL type identification" do
        # Given a transaction with mixed case sell type
        mixed_case_sell_data = valid_transaction_data.merge(
          type: "Sell_Order",
          qty: -30
        )
        transaction = described_class.new(mixed_case_sell_data)

        # When checking transaction type
        # Then it should identify as sell regardless of case
        expect(transaction.sell?).to be(true)
      end
    end

    context "when identifying dividend transactions" do
      it "identifies dividend transactions by type" do
        # Given a dividend transaction
        dividend_data = valid_transaction_data.merge(
          type: "DIVIDEND",
          qty: 0,
          amt: 125.50
        )
        transaction = described_class.new(dividend_data)

        # When checking transaction type
        # Then it should identify as dividend
        expect(transaction.dividend?).to be(true)
        expect(transaction.buy?).to be(false)
        expect(transaction.sell?).to be(false)
      end

      it "handles various dividend type formats" do
        # Given different dividend type formats
        formats = ["DIV", "DIVIDEND", "div_payment", "CASH_DIV"]

        formats.each do |div_type|
          dividend_data = valid_transaction_data.merge(type: div_type)
          transaction = described_class.new(dividend_data)

          # When checking each format
          # Then all should be identified as dividend
          expect(transaction.dividend?).to be(true), "Failed for type: #{div_type}"
        end
      end
    end

    context "when identifying fee transactions" do
      it "identifies fee transactions by type" do
        # Given a fee transaction
        fee_data = valid_transaction_data.merge(
          type: "FEE",
          qty: 0,
          amt: -2.50
        )
        transaction = described_class.new(fee_data)

        # When checking transaction type
        # Then it should identify as fee
        expect(transaction.fee?).to be(true)
      end

      it "identifies commission transactions as fees" do
        # Given a commission transaction
        commission_data = valid_transaction_data.merge(
          type: "COMMISSION",
          amt: -1.25
        )
        transaction = described_class.new(commission_data)

        # When checking transaction type
        # Then commission should be identified as fee
        expect(transaction.fee?).to be(true)
      end

      it "handles various fee type formats" do
        # Given different fee type formats
        fee_types = ["FEE", "COMMISSION", "trading_fee", "REGULATORY_FEE"]

        fee_types.each do |fee_type|
          fee_data = valid_transaction_data.merge(type: fee_type)
          transaction = described_class.new(fee_data)

          # When checking each format
          # Then all should be identified as fee
          expect(transaction.fee?).to be(true), "Failed for type: #{fee_type}"
        end
      end
    end

    context "when identifying interest transactions" do
      it "identifies interest transactions by type" do
        # Given an interest transaction
        interest_data = valid_transaction_data.merge(
          type: "INTEREST",
          qty: 0,
          amt: 15.75
        )
        transaction = described_class.new(interest_data)

        # When checking transaction type
        # Then it should identify as interest
        expect(transaction.interest?).to be(true)
      end

      it "handles various interest type formats" do
        # Given different interest type formats
        interest_types = ["INT", "INTEREST", "interest_payment", "CASH_INT"]

        interest_types.each do |int_type|
          interest_data = valid_transaction_data.merge(type: int_type)
          transaction = described_class.new(interest_data)

          # When checking each format
          # Then all should be identified as interest
          expect(transaction.interest?).to be(true), "Failed for type: #{int_type}"
        end
      end
    end
  end

  describe "value calculations" do
    context "when calculating gross value" do
      it "calculates gross value from price and quantity" do
        # Given a transaction with price and quantity
        transaction_data = valid_transaction_data.merge(
          pr: 125.50,
          qty: 200
        )
        transaction = described_class.new(transaction_data)

        # When calculating gross value
        gross_value = transaction.gross_value

        # Then it should multiply price by absolute quantity
        expect(gross_value).to eq(25100.00) # 125.50 * 200
      end

      it "uses absolute quantity for gross value calculation" do
        # Given a sell transaction with negative quantity
        sell_data = valid_transaction_data.merge(
          pr: 100.00,
          qty: -50
        )
        transaction = described_class.new(sell_data)

        # When calculating gross value
        gross_value = transaction.gross_value

        # Then it should use absolute quantity
        expect(gross_value).to eq(5000.00) # 100.00 * 50 (absolute)
      end

      it "returns calculated value based on price and quantity" do
        # Given a transaction with specific price and quantity
        specific_data = valid_transaction_data.merge(
          pr: 125.00,
          qty: 10,
          amt: 1300.00  # Amount includes fees, so gross_value will be different
        )
        transaction = described_class.new(specific_data)

        # When calculating gross value
        gross_value = transaction.gross_value

        # Then it should calculate from price * absolute quantity
        expect(gross_value).to eq(1250.00) # 125.00 * 10
      end
    end

    context "when accessing net value" do
      it "returns the transaction amount as net value" do
        # Given a transaction with amount
        transaction_data = valid_transaction_data.merge(amt: 12750.00)
        transaction = described_class.new(transaction_data)

        # When accessing net value
        net_value = transaction.net_value

        # Then it should return the amount
        expect(net_value).to eq(12750.00)
      end
    end
  end

  describe "display and formatting helpers" do
    context "when formatting quantities" do
      it "formats integer quantities without decimal places" do
        # Given a transaction with integer quantity
        integer_qty_data = valid_transaction_data.merge(qty: 100)
        transaction = described_class.new(integer_qty_data)

        # When formatting quantity
        formatted = transaction.formatted_quantity

        # Then it should display as integer
        expect(formatted).to eq("100")
      end

      it "formats fractional quantities with decimal places" do
        # Given a transaction with fractional quantity
        fractional_qty_data = valid_transaction_data.merge(qty: 100.5)
        transaction = described_class.new(fractional_qty_data)

        # When formatting quantity
        formatted = transaction.formatted_quantity

        # Then it should preserve decimal places
        expect(formatted).to eq("100.5")
      end

      it "handles negative quantities" do
        # Given a transaction with negative quantity
        negative_qty_data = valid_transaction_data.merge(qty: -75)
        transaction = described_class.new(negative_qty_data)

        # When formatting quantity
        formatted = transaction.formatted_quantity

        # Then it should preserve negative sign
        expect(formatted).to eq("-75")
      end
    end

    context "when formatting amounts" do
      it "formats amounts with default precision" do
        # Given a transaction with amount
        transaction = described_class.new(valid_transaction_data)

        # When formatting amount with default precision
        formatted = transaction.formatted_amount

        # Then it should use 2 decimal places
        expect(formatted).to eq("15025.00")
      end

      it "formats amounts with custom precision" do
        # Given a transaction with amount
        precise_data = valid_transaction_data.merge(amt: 1234.56789)
        transaction = described_class.new(precise_data)

        # When formatting amount with custom precision
        formatted = transaction.formatted_amount(precision: 4)

        # Then it should use specified precision
        expect(formatted).to eq("1234.5679")
      end

      it "handles zero precision" do
        # Given a transaction with amount
        transaction_data = valid_transaction_data.merge(amt: 1234.56)
        transaction = described_class.new(transaction_data)

        # When formatting with zero precision
        formatted = transaction.formatted_amount(precision: 0)

        # Then it should display as integer
        expect(formatted).to eq("1235") # Rounded
      end
    end

    context "when determining transaction side" do
      it "returns BUY for buy transactions" do
        # Given a buy transaction
        buy_data = valid_transaction_data.merge(type: "BUY")
        transaction = described_class.new(buy_data)

        # When getting transaction side
        side = transaction.side

        # Then it should return BUY
        expect(side).to eq("BUY")
      end

      it "returns SELL for sell transactions" do
        # Given a sell transaction with negative quantity
        sell_data = valid_transaction_data.merge(
          type: "SELL",
          qty: -100,  # Negative quantity indicates sell
          amt: -15025.00  # Negative amount for sell
        )
        transaction = described_class.new(sell_data)

        # When getting transaction side
        side = transaction.side

        # Then it should return SELL
        expect(side).to eq("SELL")
      end

      it "returns uppercased transaction type for other types" do
        # Given a dividend transaction with zero quantity
        dividend_data = valid_transaction_data.merge(
          type: "dividend",
          qty: 0,  # Zero quantity so it's neither buy nor sell
          pr: 0.0,
          amt: 87.50
        )
        transaction = described_class.new(dividend_data)

        # When getting transaction side
        side = transaction.side

        # Then it should return uppercased type
        expect(side).to eq("DIVIDEND")
      end

      it "returns OTHER for transactions with unknown type" do
        # Given a transaction with unknown type and zero quantity
        unknown_type_data = valid_transaction_data.merge(
          type: "UNKNOWN",
          qty: 0,  # Zero quantity so it's neither buy nor sell
          pr: 0.0,
          amt: 100.00
        )
        transaction = described_class.new(unknown_type_data)

        # When getting transaction side
        side = transaction.side

        # Then it should return the uppercased type
        expect(side).to eq("UNKNOWN")
      end
    end
  end

  describe "summary and reporting" do
    context "when creating summary hash" do
      it "creates comprehensive summary with key transaction data" do
        # Given a transaction
        transaction = described_class.new(valid_transaction_data)

        # When creating summary hash
        summary = transaction.summary_hash

        # Then it should include essential transaction information
        expect(summary).to include(
          date: "2024-01-15T10:30:00",
          symbol: "APPLE INC",
          side: "BUY",
          quantity: "100",
          price: 150.25,
          amount: "15025.00",
          currency: "USD",
          type: "BUY"
        )
      end

      it "creates complete summary with all required transaction data" do
        # Given a complete transaction
        transaction = described_class.new(valid_transaction_data)

        # When creating summary hash
        summary = transaction.summary_hash

        # Then it should include all transaction data
        expect(summary).to include(:date, :symbol, :side, :quantity, :price, :amount, :currency, :type)
        expect(summary[:symbol]).to eq("APPLE INC")
        expect(summary[:side]).to eq("BUY")
      end
    end
  end

  describe "time-based analysis" do
    context "when checking if transaction is recent" do
      it "identifies recent transactions within default timeframe" do
        # Given a transaction from yesterday
        recent_date = (Date.today - 1).strftime("%Y-%m-%d")
        recent_data = valid_transaction_data.merge(date: recent_date)
        transaction = described_class.new(recent_data)

        # When checking if recent
        # Then it should be identified as recent
        expect(transaction.recent?).to be(true)
      end

      it "identifies old transactions outside default timeframe" do
        # Given a transaction from 45 days ago
        old_date = (Date.today - 45).strftime("%Y-%m-%d")
        old_data = valid_transaction_data.merge(date: old_date)
        transaction = described_class.new(old_data)

        # When checking if recent
        # Then it should not be identified as recent
        expect(transaction.recent?).to be(false)
      end

      it "allows custom timeframe for recency check" do
        # Given a transaction from 10 days ago
        custom_date = (Date.today - 10).strftime("%Y-%m-%d")
        custom_data = valid_transaction_data.merge(date: custom_date)
        transaction = described_class.new(custom_data)

        # When checking with custom timeframe
        # Then it should respect custom days parameter
        expect(transaction.recent?(7)).to be(false)   # 10 days > 7 days
        expect(transaction.recent?(15)).to be(true)   # 10 days < 15 days
      end

      it "returns false for transactions with unparseable dates" do
        # Given a transaction with invalid date
        invalid_date_data = valid_transaction_data.merge(date: "invalid")
        transaction = described_class.new(invalid_date_data)

        # When checking if recent
        # Then it should return false
        expect(transaction.recent?).to be(false)
      end
    end

    context "when checking if transaction is significant" do
      it "identifies large transactions above default threshold" do
        # Given a large transaction
        large_data = valid_transaction_data.merge(amt: 5000.00)
        transaction = described_class.new(large_data)

        # When checking if significant
        # Then it should be identified as significant
        expect(transaction.significant?).to be(true)
      end

      it "identifies small transactions below default threshold" do
        # Given a small transaction
        small_data = valid_transaction_data.merge(amt: 500.00)
        transaction = described_class.new(small_data)

        # When checking if significant
        # Then it should not be identified as significant
        expect(transaction.significant?).to be(false)
      end

      it "allows custom threshold for significance check" do
        # Given a medium-sized transaction
        medium_data = valid_transaction_data.merge(amt: 2500.00)
        transaction = described_class.new(medium_data)

        # When checking with custom threshold
        # Then it should respect custom threshold
        expect(transaction.significant?(3000.00)).to be(false) # 2500 < 3000
        expect(transaction.significant?(2000.00)).to be(true)  # 2500 > 2000
      end

      it "uses absolute amount for significance check" do
        # Given a transaction with negative amount
        negative_data = valid_transaction_data.merge(amt: -2500.00)
        transaction = described_class.new(negative_data)

        # When checking if significant
        # Then it should use absolute amount
        expect(transaction.significant?(2000.00)).to be(true) # |−2500| > 2000
      end
    end
  end

  describe "class-level utility methods" do
    let(:sample_transactions) do
      [
        described_class.new(valid_transaction_data.merge(type: "BUY", amt: 1000.00)),
        described_class.new(valid_transaction_data.merge(type: "SELL", amt: -800.00)),
        described_class.new(valid_transaction_data.merge(type: "DIVIDEND", amt: 50.00)),
        described_class.new(valid_transaction_data.merge(type: "BUY", amt: 1500.00))
      ]
    end

    context "when grouping transactions by type" do
      it "groups transactions by their transaction type" do
        # Given an array of transactions with different types
        # When grouping by type
        grouped = described_class.group_by_type(sample_transactions)

        # Then transactions should be grouped by type
        expect(grouped.keys).to contain_exactly("BUY", "SELL", "DIVIDEND")
        expect(grouped["BUY"].size).to eq(2)
        expect(grouped["SELL"].size).to eq(1)
        expect(grouped["DIVIDEND"].size).to eq(1)
      end

      it "handles empty transaction array" do
        # Given an empty array
        # When grouping by type
        grouped = described_class.group_by_type([])

        # Then it should return empty hash
        expect(grouped).to eq({})
      end
    end

    context "when calculating total value" do
      it "sums all transaction amounts" do
        # Given an array of transactions
        # When calculating total value
        total = described_class.total_value(sample_transactions)

        # Then it should sum all amounts
        expected_total = 1000.00 + -800.00 + 50.00 + 1500.00
        expect(total).to eq(expected_total)
        expect(total).to eq(1750.00)
      end

      it "handles empty transaction array" do
        # Given an empty array
        # When calculating total value
        total = described_class.total_value([])

        # Then it should return zero
        expect(total).to eq(0)
      end
    end

    context "when filtering by date range" do
      let(:date_range_transactions) do
        [
          described_class.new(valid_transaction_data.merge(date: "2024-01-10")),
          described_class.new(valid_transaction_data.merge(date: "2024-01-15")),
          described_class.new(valid_transaction_data.merge(date: "2024-01-20")),
          described_class.new(valid_transaction_data.merge(date: "2024-01-25")),
          described_class.new(valid_transaction_data.merge(date: "invalid-date"))
        ]
      end

      it "filters transactions within date range" do
        # Given transactions with various dates
        start_date = Date.new(2024, 1, 12)
        end_date = Date.new(2024, 1, 22)

        # When filtering by date range
        filtered = described_class.in_date_range(date_range_transactions, start_date, end_date)

        # Then only transactions within range should be included
        expect(filtered.size).to eq(2) # Jan 15 and Jan 20
        filtered_dates = filtered.map(&:transaction_date)
        expect(filtered_dates).to include(Date.new(2024, 1, 15))
        expect(filtered_dates).to include(Date.new(2024, 1, 20))
      end

      it "excludes transactions with unparseable dates" do
        # Given transactions including ones with invalid dates
        start_date = Date.new(2024, 1, 1)
        end_date = Date.new(2024, 1, 31)

        # When filtering by date range
        filtered = described_class.in_date_range(date_range_transactions, start_date, end_date)

        # Then transactions with invalid dates should be excluded
        expect(filtered.size).to eq(4) # All valid dates, excluding invalid one
      end

      it "includes boundary dates" do
        # Given transactions on boundary dates
        start_date = Date.new(2024, 1, 15)
        end_date = Date.new(2024, 1, 20)

        # When filtering by date range
        filtered = described_class.in_date_range(date_range_transactions, start_date, end_date)

        # Then boundary dates should be included
        expect(filtered.size).to eq(2) # Jan 15 and Jan 20
        filtered_dates = filtered.map(&:transaction_date)
        expect(filtered_dates).to include(start_date)
        expect(filtered_dates).to include(end_date)
      end
    end
  end

  describe "real-world transaction scenarios" do
    it "handles stock purchase transaction from IBKR API" do
      # Given a typical stock purchase
      stock_purchase = {
        date: "2024-03-15T09:30:00",
        cur: "USD",
        pr: 142.50,
        qty: 100,
        amt: 14250.00,
        conid: 265598,
        desc: "APPLE INC",
        type: "BUY"
      }

      transaction = described_class.new(stock_purchase)

      expect(transaction.buy?).to be(true)
      expect(transaction.side).to eq("BUY")
      expect(transaction.gross_value).to eq(14250.00)
      expect(transaction.formatted_quantity).to eq("100")
      expect(transaction.recent?).to be(false) # 2024-03-15 is not recent relative to today
      expect(transaction.significant?).to be(true) # Above $1000 default
    end

    it "handles dividend payment transaction" do
      # Given a dividend payment
      dividend_payment = {
        date: "2024-03-20T00:00:00",
        cur: "USD",
        pr: 0.00,
        qty: 0,
        amt: 87.50,
        conid: 265598,
        desc: "APPLE INC - DIVIDEND",
        type: "DIVIDEND"
      }

      transaction = described_class.new(dividend_payment)

      expect(transaction.dividend?).to be(true)
      expect(transaction.buy?).to be(false)
      expect(transaction.sell?).to be(false)
      expect(transaction.side).to eq("DIVIDEND")
      expect(transaction.gross_value).to eq(0.0) # 0.00 * 0 = 0.0
      expect(transaction.significant?(50.00)).to be(true)
    end

    it "handles fractional share transaction" do
      # Given a fractional share purchase
      fractional_purchase = {
        date: "2024-03-18T14:15:30",
        cur: "USD",
        pr: 175.25,
        qty: 2.5,
        amt: 438.13,
        conid: 11005391,
        desc: "GOOGLE CLASS A",
        type: "BUY"
      }

      transaction = described_class.new(fractional_purchase)

      expect(transaction.buy?).to be(true)
      expect(transaction.formatted_quantity).to eq("2.5")
      expect(transaction.gross_value).to eq(438.125) # 175.25 * 2.5
      expect(transaction.formatted_amount).to eq("438.13")
    end

    it "handles commission fee transaction" do
      # Given a commission fee
      commission_fee = {
        date: "2024-03-15T09:30:01",
        cur: "USD",
        pr: 0.00,
        qty: 0,
        amt: -1.25,
        conid: 0,
        desc: "COMMISSION - STOCK TRADE",
        type: "COMMISSION"
      }

      transaction = described_class.new(commission_fee)

      expect(transaction.fee?).to be(true)
      expect(transaction.side).to eq("COMMISSION")
      expect(transaction.amount).to be < 0
      expect(transaction.significant?(1.00)).to be(true) # Absolute value
    end

    it "handles international stock transaction with currency conversion" do
      # Given an international stock transaction
      international_trade = {
        date: "2024-03-19T10:00:00",
        cur: "EUR",
        pr: 45.75,
        qty: 200,
        amt: 9150.00,
        conid: 67891234,
        desc: "ASML HOLDING NV",
        type: "BUY"
      }

      transaction = described_class.new(international_trade)

      expect(transaction.currency).to eq("EUR")
      expect(transaction.buy?).to be(true)
      expect(transaction.gross_value).to eq(9150.00)
      expect(transaction.summary_hash[:currency]).to eq("EUR")
    end
  end

  describe "validation failures" do
    context "when required attributes are missing" do
      it "raises error for missing date" do
        invalid_data = valid_transaction_data.except(:date)
        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "raises error for missing currency" do
        invalid_data = valid_transaction_data.except(:cur)
        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      %i[pr qty amt conid desc type].each do |required_field|
        it "raises error for missing #{required_field}" do
          invalid_data = valid_transaction_data.except(required_field)
          expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
        end
      end
    end

    context "when attributes have wrong types" do
      it "raises error for non-numeric price" do
        invalid_data = valid_transaction_data.merge(pr: "not_a_number")
        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "raises error for non-numeric quantity" do
        invalid_data = valid_transaction_data.merge(qty: "invalid_quantity")
        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "raises error for non-string description" do
        invalid_data = valid_transaction_data.merge(desc: 123456)
        expect { described_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end
    end
  end

  private

  let(:valid_transaction_data) do
    {
      date: "2024-01-15T10:30:00",
      cur: "USD",
      pr: 150.25,
      qty: 100,
      amt: 15025.00,
      conid: 265598,
      desc: "APPLE INC",
      type: "BUY"
    }
  end
end
