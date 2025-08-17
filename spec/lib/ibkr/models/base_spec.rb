# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Models::Base do
  # Create a test model class to test Base functionality
  let(:test_model_class) do
    Class.new(described_class) do
      attribute :name, Ibkr::Types::String
      attribute :value, Ibkr::Types::Integer
      attribute? :optional_field, Ibkr::Types::String.optional
      attribute? :nullable_amount, Ibkr::Types::IbkrNumber.optional
    end
  end

  let(:valid_data) do
    {
      "name" => "Test Model",
      "value" => 42,
      "optional_field" => "optional_value",
      "nullable_amount" => 123.45
    }
  end

  describe "model inheritance and structure" do
    context "when creating a model class that inherits from Base" do
      it "inherits from Dry::Struct" do
        # Given the Base class
        # When checking inheritance
        # Then Base should inherit from Dry::Struct
        expect(described_class.superclass).to eq(Dry::Struct)
      end

      it "allows defining attributes in child classes" do
        # Given a test model class with attributes
        # When creating an instance
        model = test_model_class.new(valid_data)

        # Then it should have defined attributes accessible
        expect(model).to respond_to(:name)
        expect(model).to respond_to(:value)
        expect(model).to respond_to(:optional_field)
        expect(model).to respond_to(:nullable_amount)
      end
    end
  end

  describe "key transformation behavior" do
    context "when creating model with string keys" do
      it "transforms string keys to symbols automatically" do
        # Given data with string keys
        string_key_data = {
          "name" => "String Key Test",
          "value" => 100
        }

        # When creating model instance
        model = test_model_class.new(string_key_data)

        # Then it should transform keys and make data accessible
        expect(model.name).to eq("String Key Test")
        expect(model.value).to eq(100)
      end

      it "handles mixed string and symbol keys" do
        # Given data with mixed key types
        mixed_key_data = {
          "name" => "Mixed Keys",
          :value => 200,
          "optional_field" => "test"
        }

        # When creating model instance
        model = test_model_class.new(mixed_key_data)

        # Then all keys should be accessible regardless of original type
        expect(model.name).to eq("Mixed Keys")
        expect(model.value).to eq(200)
        expect(model.optional_field).to eq("test")
      end
    end

    context "when creating model with symbol keys" do
      it "works with symbol keys directly" do
        # Given data with symbol keys
        symbol_key_data = {
          name: "Symbol Key Test",
          value: 300
        }

        # When creating model instance
        model = test_model_class.new(symbol_key_data)

        # Then it should work with symbol keys
        expect(model.name).to eq("Symbol Key Test")
        expect(model.value).to eq(300)
      end
    end
  end

  describe "hash conversion and serialization" do
    context "when converting model to hash" do
      it "converts model to hash with compact behavior" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When converting to hash
        hash = model.to_h

        # Then it should return hash with symbol keys
        expect(hash).to be_a(Hash)
        expect(hash).to include(
          name: "Test Model",
          value: 42,
          optional_field: "optional_value",
          nullable_amount: 123.45
        )
      end

      it "compacts hash by removing nil values" do
        # Given a model with nil optional values
        data_with_nils = {
          name: "Test with Nils",
          value: 50,
          optional_field: nil,
          nullable_amount: nil
        }
        model = test_model_class.new(data_with_nils)

        # When converting to hash
        hash = model.to_h

        # Then nil values should be removed
        expect(hash).to include(name: "Test with Nils", value: 50)
        expect(hash).not_to have_key(:optional_field)
        expect(hash).not_to have_key(:nullable_amount)
      end

      it "preserves zero and false values during compacting" do
        # Given a model with zero and false values
        special_values_class = Class.new(described_class) do
          attribute :name, Ibkr::Types::String
          attribute :zero_value, Ibkr::Types::Integer
          attribute :false_value, Ibkr::Types::Bool
        end

        model = special_values_class.new(
          name: "Special Values Test",
          zero_value: 0,
          false_value: false
        )

        # When converting to hash
        hash = model.to_h

        # Then zero and false should be preserved
        expect(hash).to include(
          name: "Special Values Test",
          zero_value: 0,
          false_value: false
        )
      end
    end

    context "when converting model to JSON" do
      it "converts model to JSON string" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When converting to JSON
        json_string = model.to_json

        # Then it should return valid JSON
        expect(json_string).to be_a(String)
        parsed = JSON.parse(json_string)
        expect(parsed).to include(
          "name" => "Test Model",
          "value" => 42,
          "optional_field" => "optional_value",
          "nullable_amount" => 123.45
        )
      end

      it "passes through JSON options" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When converting to JSON with options
        json_string = model.to_json(pretty: true)

        # Then it should handle JSON options
        expect(json_string).to be_a(String)
        expect(JSON.parse(json_string)).to be_a(Hash)
      end

      it "handles models with nil values in JSON conversion" do
        # Given a model with nil values
        data_with_nils = valid_data.merge(optional_field: nil)
        model = test_model_class.new(data_with_nils)

        # When converting to JSON
        json_string = model.to_json

        # Then nil values should be excluded (due to compact)
        parsed = JSON.parse(json_string)
        expect(parsed).not_to have_key("optional_field")
      end
    end
  end

  describe "attribute checking and access" do
    context "when checking attribute presence" do
      it "identifies existing attributes" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When checking for existing attributes
        # Then it should return true for defined attributes
        expect(model.has_attribute?(:name)).to be(true)
        expect(model.has_attribute?(:value)).to be(true)
        expect(model.has_attribute?(:optional_field)).to be(true)
        expect(model.has_attribute?("name")).to be(true) # String key
      end

      it "identifies non-existing attributes" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When checking for non-existing attributes
        # Then it should return false
        expect(model.has_attribute?(:nonexistent)).to be(false)
        expect(model.has_attribute?("missing_field")).to be(false)
      end

      it "works with both symbol and string attribute names" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When checking attributes with different key types
        # Then both should work
        expect(model.has_attribute?(:name)).to be(true)
        expect(model.has_attribute?("name")).to be(true)
        expect(model.has_attribute?(:value)).to be(true)
        expect(model.has_attribute?("value")).to be(true)
      end
    end

    context "when accessing attribute values with defaults" do
      it "returns actual value when attribute exists and has value" do
        # Given a model with values
        model = test_model_class.new(valid_data)

        # When accessing attribute with default
        value = model.attribute_value(:name, "default_name")

        # Then it should return actual value
        expect(value).to eq("Test Model")
      end

      it "returns default when attribute exists but is nil" do
        # Given a model with nil optional attribute
        data_with_nil = valid_data.merge(optional_field: nil)
        model = test_model_class.new(data_with_nil)

        # When accessing nil attribute with default
        value = model.attribute_value(:optional_field, "default_value")

        # Then it should return default
        expect(value).to eq("default_value")
      end

      it "returns default when attribute does not exist" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When accessing non-existent attribute with default
        value = model.attribute_value(:nonexistent, "fallback_value")

        # Then it should return default
        expect(value).to eq("fallback_value")
      end

      it "returns nil default when no default specified" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When accessing non-existent attribute without default
        value = model.attribute_value(:nonexistent)

        # Then it should return nil
        expect(value).to be_nil
      end

      it "preserves falsy values that are not nil" do
        # Given a model with falsy but non-nil values
        falsy_values_class = Class.new(described_class) do
          attribute :zero_value, Ibkr::Types::Integer
          attribute :false_value, Ibkr::Types::Bool
          attribute :empty_string, Ibkr::Types::String
        end

        model = falsy_values_class.new(
          zero_value: 0,
          false_value: false,
          empty_string: ""
        )

        # When accessing falsy attributes with defaults
        # Then actual falsy values should be returned, not defaults
        expect(model.attribute_value(:zero_value, 999)).to eq(0)
        expect(model.attribute_value(:false_value, true)).to be(false)
        expect(model.attribute_value(:empty_string, "default")).to eq("")
      end
    end
  end

  describe "debugging and inspection" do
    context "when inspecting model instances" do
      it "provides readable inspect output with class name and attributes" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When inspecting the model
        inspect_output = model.inspect

        # Then it should include attributes in readable format
        expect(inspect_output).to include("name=\"Test Model\"")
        expect(inspect_output).to include("value=42")
        expect(inspect_output).to include("optional_field=\"optional_value\"")
        expect(inspect_output).to include("nullable_amount=123.45")
        expect(inspect_output).to start_with("#<")
        expect(inspect_output).to end_with(">")
      end

      it "handles models with nil values in inspect" do
        # Given a model with nil values
        data_with_nils = {
          name: "Nil Test",
          value: 100,
          optional_field: nil,
          nullable_amount: nil
        }
        model = test_model_class.new(data_with_nils)

        # When inspecting the model
        inspect_output = model.inspect

        # Then it should handle nil values gracefully
        expect(inspect_output).to include("name=\"Nil Test\"")
        expect(inspect_output).to include("value=100")
        # Nil values are compacted, so they shouldn't appear
        expect(inspect_output).not_to include("optional_field=")
        expect(inspect_output).not_to include("nullable_amount=")
      end

      it "formats inspect output properly" do
        # Given a model instance
        model = test_model_class.new(valid_data)

        # When inspecting the model
        inspect_output = model.inspect

        # Then it should follow expected format pattern
        expect(inspect_output).to match(/#<.+ .+>/)
        expect(inspect_output).to start_with("#<")
        expect(inspect_output).to end_with(">")
      end
    end
  end

  describe "edge cases and error handling" do
    context "when handling special data types" do
      it "works with complex nested data" do
        # Given a model with nested structure capability
        nested_model_class = Class.new(described_class) do
          attribute :name, Ibkr::Types::String
          attribute :metadata, Ibkr::Types::Hash
        end

        nested_data = {
          name: "Nested Test",
          metadata: {
            created_at: "2024-01-01",
            tags: ["test", "model"],
            config: {enabled: true}
          }
        }

        # When creating model with nested data
        model = nested_model_class.new(nested_data)

        # Then it should handle nested structures
        expect(model.name).to eq("Nested Test")
        expect(model.metadata).to be_a(Hash)
        expect(model.metadata[:tags]).to eq(["test", "model"])
      end

      it "handles empty data gracefully" do
        # Given a model that allows empty optional fields
        minimal_model_class = Class.new(described_class) do
          attribute? :optional_name, Ibkr::Types::String.optional
          attribute? :optional_value, Ibkr::Types::Integer.optional
        end

        # When creating model with empty data
        model = minimal_model_class.new({})

        # Then it should create successfully
        expect(model.optional_name).to be_nil
        expect(model.optional_value).to be_nil
        expect(model.to_h).to eq({})
      end
    end

    context "when handling type coercion failures" do
      it "propagates type validation errors from Dry::Struct" do
        # Given invalid data that cannot be coerced
        invalid_data = {
          name: "Valid Name",
          value: "not_an_integer" # Invalid for integer type
        }

        # When creating model with invalid data
        # Then it should raise type validation error
        expect { test_model_class.new(invalid_data) }.to raise_error(Dry::Struct::Error)
      end

      it "provides meaningful error context for validation failures" do
        # Given completely invalid data
        invalid_data = {
          name: 12345, # Should be string
          value: "invalid_integer"
        }

        # When creating model with invalid data
        # Then error should provide context
        expect { test_model_class.new(invalid_data) }.to raise_error do |error|
          expect(error).to be_a(Dry::Struct::Error)
          expect(error.message).to be_a(String)
        end
      end
    end
  end

  describe "integration with IBKR type system" do
    context "when using IBKR-specific types" do
      it "works with IbkrNumber type for financial data" do
        # Given a model using IbkrNumber type
        financial_model_class = Class.new(described_class) do
          attribute :symbol, Ibkr::Types::String
          attribute :price, Ibkr::Types::IbkrNumber
          attribute :amount, Ibkr::Types::IbkrNumber
        end

        # When creating model with numeric data
        financial_data = {
          symbol: "AAPL",
          price: "150.25", # String that should coerce to number
          amount: 15025.00
        }
        model = financial_model_class.new(financial_data)

        # Then IbkrNumber should handle coercion properly
        expect(model.symbol).to eq("AAPL")
        expect(model.price).to eq(150.25)
        expect(model.amount).to eq(15025.00)
      end

      it "handles optional IBKR types" do
        # Given a model with optional IBKR types
        optional_model_class = Class.new(described_class) do
          attribute :required_field, Ibkr::Types::String
          attribute? :optional_number, Ibkr::Types::IbkrNumber.optional
        end

        # When creating model with partial data
        partial_data = {required_field: "Required Value"}
        model = optional_model_class.new(partial_data)

        # Then it should handle optional fields properly
        expect(model.required_field).to eq("Required Value")
        expect(model.optional_number).to be_nil
        expect(model.has_attribute?(:optional_number)).to be(true)
      end
    end
  end

  describe "real-world usage scenarios" do
    context "when modeling IBKR API responses" do
      it "models account summary data structure" do
        # Given an account summary model structure
        account_summary_model = Class.new(described_class) do
          attribute :account_id, Ibkr::Types::String
          attribute :net_liquidation, Ibkr::Types::IbkrNumber
          attribute :total_cash, Ibkr::Types::IbkrNumber
          attribute? :buying_power, Ibkr::Types::IbkrNumber.optional
        end

        summary_data = {
          "account_id" => "DU123456",
          "net_liquidation" => 100000.50,
          "total_cash" => 25000.00
        }

        # When creating account summary model
        summary = account_summary_model.new(summary_data)

        # Then it should model account data properly
        expect(summary.account_id).to eq("DU123456")
        expect(summary.net_liquidation).to eq(100000.50)
        expect(summary.total_cash).to eq(25000.00)
        expect(summary.buying_power).to be_nil
        expect(summary.to_h).to include(:account_id, :net_liquidation, :total_cash)
      end

      it "models transaction data from API" do
        # Given a transaction model structure
        transaction_model = Class.new(described_class) do
          attribute :transaction_id, Ibkr::Types::String
          attribute :symbol, Ibkr::Types::String
          attribute :quantity, Ibkr::Types::IbkrNumber
          attribute :price, Ibkr::Types::IbkrNumber
          attribute :transaction_date, Ibkr::Types::String
        end

        transaction_data = {
          "transaction_id" => "T123456",
          "symbol" => "AAPL",
          "quantity" => 100,
          "price" => "150.25",
          "transaction_date" => "2024-01-15"
        }

        # When creating transaction model
        transaction = transaction_model.new(transaction_data)

        # Then it should model transaction data properly
        expect(transaction.transaction_id).to eq("T123456")
        expect(transaction.symbol).to eq("AAPL")
        expect(transaction.quantity).to eq(100)
        expect(transaction.price).to eq(150.25)
        expect(transaction.to_json).to include("T123456", "AAPL")
      end
    end

    context "when used in service response transformation" do
      it "supports array transformation workflows" do
        # Given multiple model instances
        data_array = [
          {name: "Model 1", value: 100},
          {name: "Model 2", value: 200},
          {name: "Model 3", value: 300}
        ]

        # When transforming array to models
        models = data_array.map { |data| test_model_class.new(data) }

        # Then each should be properly transformed
        expect(models.size).to eq(3)
        expect(models.all? { |m| m.is_a?(test_model_class) }).to be(true)
        expect(models.map(&:name)).to eq(["Model 1", "Model 2", "Model 3"])
        expect(models.map(&:value)).to eq([100, 200, 300])
      end

      it "supports filtering and selection based on attributes" do
        # Given models with different characteristics
        mixed_data = [
          {name: "High Value", value: 1000},
          {name: "Low Value", value: 10},
          {name: "Medium Value", value: 500}
        ]
        models = mixed_data.map { |data| test_model_class.new(data) }

        # When filtering models
        high_value_models = models.select { |m| m.value > 100 }

        # Then filtering should work on model attributes
        expect(high_value_models.size).to eq(2)
        expect(high_value_models.map(&:name)).to contain_exactly("High Value", "Medium Value")
      end
    end
  end
end
