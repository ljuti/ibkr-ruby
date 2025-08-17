# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Services::Base do
  let(:mock_client) do
    double("client",
      authenticated?: true,
      account_id: "DU123456",
      get: {"result" => "success"},
      post: {"created" => true},
      put: {"updated" => true},
      delete: {"deleted" => true})
  end

  let(:service) { described_class.new(mock_client) }

  describe "service initialization" do
    context "when creating a new service instance" do
      it "stores reference to the client" do
        # Given a client instance
        # When creating a new service
        service = described_class.new(mock_client)

        # Then it should store the client reference
        expect(service.client).to eq(mock_client)
      end

      it "makes the client accessible as an attribute reader" do
        # Given a service instance
        service = described_class.new(mock_client)

        # When accessing the client
        # Then it should be accessible via attribute reader
        expect(service).to respond_to(:client)
        expect(service.client).to be(mock_client)
      end
    end
  end

  describe "HTTP method delegation" do
    context "when making GET requests" do
      it "delegates GET requests to the client" do
        # Given a service with a mock client
        path = "/api/test"
        options = {params: {id: 123}}

        # When making a GET request
        expect(mock_client).to receive(:get).with(path, **options).and_return({"data" => "test"})
        result = service.send(:get, path, **options)

        # Then it should delegate to client and return response
        expect(result).to eq({"data" => "test"})
      end

      it "passes through all options to client GET method" do
        # Given a service and request options
        path = "/api/endpoint"
        options = {headers: {"Accept" => "application/json"}, params: {limit: 50}}

        # When making GET request with options
        expect(mock_client).to receive(:get).with(path, **options)
        service.send(:get, path, **options)

        # Then all options should be passed through
      end
    end

    context "when making POST requests" do
      it "delegates POST requests to the client" do
        # Given a service with a mock client
        path = "/api/create"
        options = {body: {name: "test"}}

        # When making a POST request
        expect(mock_client).to receive(:post).with(path, **options).and_return({"id" => 1})
        result = service.send(:post, path, **options)

        # Then it should delegate to client and return response
        expect(result).to eq({"id" => 1})
      end

      it "handles POST requests with JSON body" do
        # Given a service and JSON data
        path = "/api/orders"
        json_data = {symbol: "AAPL", quantity: 100, side: "BUY"}
        options = {json: json_data}

        # When making POST request with JSON
        expect(mock_client).to receive(:post).with(path, **options)
        service.send(:post, path, **options)

        # Then JSON data should be passed through
      end
    end

    context "when making PUT requests" do
      it "delegates PUT requests to the client" do
        # Given a service with a mock client
        path = "/api/update/123"
        options = {body: {status: "active"}}

        # When making a PUT request
        expect(mock_client).to receive(:put).with(path, **options).and_return({"updated" => true})
        result = service.send(:put, path, **options)

        # Then it should delegate to client and return response
        expect(result).to eq({"updated" => true})
      end
    end

    context "when making DELETE requests" do
      it "delegates DELETE requests to the client" do
        # Given a service with a mock client
        path = "/api/delete/456"
        options = {params: {force: true}}

        # When making a DELETE request
        expect(mock_client).to receive(:delete).with(path, **options).and_return({"deleted" => true})
        result = service.send(:delete, path, **options)

        # Then it should delegate to client and return response
        expect(result).to eq({"deleted" => true})
      end
    end
  end

  describe "authentication checking" do
    context "when client is authenticated" do
      it "allows requests to proceed when client is authenticated" do
        # Given an authenticated client
        allow(mock_client).to receive(:authenticated?).and_return(true)

        # When checking authentication
        # Then it should not raise an error
        expect { service.send(:ensure_authenticated!) }.not_to raise_error
      end
    end

    context "when client is not authenticated" do
      it "raises authentication error when client is not authenticated" do
        # Given an unauthenticated client
        allow(mock_client).to receive(:authenticated?).and_return(false)

        # When checking authentication
        # Then it should raise authentication error
        expect { service.send(:ensure_authenticated!) }.to raise_error(
          Ibkr::AuthenticationError,
          "Client must be authenticated before making API calls"
        )
      end

      it "provides clear error message for authentication failure" do
        # Given an unauthenticated client
        unauthenticated_client = double("client", authenticated?: false)
        service = described_class.new(unauthenticated_client)

        # When checking authentication
        # Then error message should be descriptive
        expect { service.send(:ensure_authenticated!) }.to raise_error do |error|
          expect(error).to be_a(Ibkr::AuthenticationError)
          expect(error.message).to include("Client must be authenticated")
          expect(error.message).to include("before making API calls")
        end
      end
    end
  end

  describe "account ID management" do
    context "when accessing account ID" do
      it "returns the current account ID from client" do
        # Given a client with account ID
        allow(mock_client).to receive(:account_id).and_return("DU789012")

        # When accessing account ID through service
        account_id = service.send(:account_id)

        # Then it should return client's account ID
        expect(account_id).to eq("DU789012")
      end

      it "delegates to client for account ID retrieval" do
        # Given a service
        # When accessing account ID
        expect(mock_client).to receive(:account_id).and_return("DU123456")
        result = service.send(:account_id)

        # Then it should delegate to client
        expect(result).to eq("DU123456")
      end

      it "handles nil account ID from client" do
        # Given a client without account ID
        allow(mock_client).to receive(:account_id).and_return(nil)

        # When accessing account ID
        account_id = service.send(:account_id)

        # Then it should return nil
        expect(account_id).to be_nil
      end
    end
  end

  describe "response transformation" do
    let(:mock_model_class) do
      Class.new do
        attr_reader :data

        def initialize(data)
          @data = data
        end

        def ==(other)
          other.is_a?(self.class) && data == other.data
        end
      end
    end

    context "when transforming hash responses" do
      it "transforms single hash response using model class" do
        # Given a hash response and model class
        response = {"name" => "test", "value" => 123}

        # When transforming response
        result = service.send(:transform_response, response, mock_model_class)

        # Then it should create model instance from hash
        expect(result).to be_a(mock_model_class)
        expect(result.data).to eq(response)
      end
    end

    context "when transforming array responses" do
      it "transforms array response by mapping each item to model class" do
        # Given an array response and model class
        response = [
          {"name" => "item1", "value" => 1},
          {"name" => "item2", "value" => 2}
        ]

        # When transforming response
        result = service.send(:transform_response, response, mock_model_class)

        # Then it should return array of model instances
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first).to be_a(mock_model_class)
        expect(result.last).to be_a(mock_model_class)
        expect(result.first.data).to eq(response.first)
        expect(result.last.data).to eq(response.last)
      end

      it "handles empty array responses" do
        # Given an empty array response
        response = []

        # When transforming response
        result = service.send(:transform_response, response, mock_model_class)

        # Then it should return empty array
        expect(result).to eq([])
        expect(result).to be_an(Array)
      end
    end

    context "when handling non-transformable responses" do
      it "returns response unchanged for non-hash, non-array types" do
        # Given a string response
        response = "simple string"

        # When transforming response
        result = service.send(:transform_response, response, mock_model_class)

        # Then it should return original response unchanged
        expect(result).to eq("simple string")
      end

      it "returns numeric responses unchanged" do
        # Given a numeric response
        response = 42

        # When transforming response
        result = service.send(:transform_response, response, mock_model_class)

        # Then it should return original number
        expect(result).to eq(42)
      end

      it "returns nil responses unchanged" do
        # Given a nil response
        response = nil

        # When transforming response
        result = service.send(:transform_response, response, mock_model_class)

        # Then it should return nil
        expect(result).to be_nil
      end
    end

    context "when model class raises errors during initialization" do
      let(:failing_model_class) do
        Class.new do
          def initialize(data)
            raise ArgumentError, "Invalid data: #{data}"
          end
        end
      end

      it "propagates model initialization errors" do
        # Given a model class that raises errors
        response = {"invalid" => "data"}

        # When transforming response with failing model
        # Then it should propagate the error
        expect {
          service.send(:transform_response, response, failing_model_class)
        }.to raise_error(ArgumentError, /Invalid data/)
      end
    end
  end

  describe "path building helpers" do
    context "when building account-specific paths" do
      it "builds path with account ID prefix" do
        # Given a service with account ID
        allow(mock_client).to receive(:account_id).and_return("DU123456")
        path_suffix = "/positions"

        # When building account path
        full_path = service.send(:account_path, path_suffix)

        # Then it should include account ID in path
        expect(full_path).to eq("/v1/api/portfolio/DU123456/positions")
      end

      it "handles paths that start with slash" do
        # Given a path that starts with slash
        allow(mock_client).to receive(:account_id).and_return("DU789012")
        path_suffix = "/summary"

        # When building account path
        full_path = service.send(:account_path, path_suffix)

        # Then it should construct proper path
        expect(full_path).to eq("/v1/api/portfolio/DU789012/summary")
      end

      it "handles paths without leading slash" do
        # Given a path without leading slash
        allow(mock_client).to receive(:account_id).and_return("DU456789")
        path_suffix = "transactions"

        # When building account path
        full_path = service.send(:account_path, path_suffix)

        # Then it should construct proper path
        expect(full_path).to eq("/v1/api/portfolio/DU456789transactions")
      end

      it "handles empty path suffix" do
        # Given an empty path suffix
        allow(mock_client).to receive(:account_id).and_return("DU999999")
        path_suffix = ""

        # When building account path
        full_path = service.send(:account_path, path_suffix)

        # Then it should return base portfolio path
        expect(full_path).to eq("/v1/api/portfolio/DU999999")
      end
    end

    context "when building general API paths" do
      it "builds general API path with version prefix" do
        # Given a general API path
        path_suffix = "/accounts"

        # When building API path
        full_path = service.send(:api_path, path_suffix)

        # Then it should include API version prefix
        expect(full_path).to eq("/v1/api/accounts")
      end

      it "handles paths with leading slash" do
        # Given a path with leading slash
        path_suffix = "/iserver/auth/status"

        # When building API path
        full_path = service.send(:api_path, path_suffix)

        # Then it should construct proper path
        expect(full_path).to eq("/v1/api/iserver/auth/status")
      end

      it "handles paths without leading slash" do
        # Given a path without leading slash
        path_suffix = "market/data"

        # When building API path
        full_path = service.send(:api_path, path_suffix)

        # Then it should construct proper path
        expect(full_path).to eq("/v1/apimarket/data")
      end

      it "handles empty path suffix" do
        # Given an empty path suffix
        path_suffix = ""

        # When building API path
        full_path = service.send(:api_path, path_suffix)

        # Then it should return base API path
        expect(full_path).to eq("/v1/api")
      end
    end
  end

  describe "integration scenarios" do
    let(:mock_model_class) do
      Class.new do
        attr_reader :data

        def initialize(data)
          @data = data
        end

        def ==(other)
          other.is_a?(self.class) && data == other.data
        end
      end
    end

    context "when making authenticated API calls" do
      it "checks authentication before making requests" do
        # Given a service that checks authentication
        service_class = Class.new(described_class) do
          def test_method
            ensure_authenticated!
            get("/test/endpoint")
          end
        end

        authenticated_service = service_class.new(mock_client)

        # When making authenticated request
        expect(mock_client).to receive(:authenticated?).and_return(true)
        expect(mock_client).to receive(:get).with("/test/endpoint")

        # Then it should check authentication first
        authenticated_service.test_method
      end

      it "fails fast when authentication is missing" do
        # Given an unauthenticated client
        unauthenticated_client = double("client", authenticated?: false)
        service_class = Class.new(described_class) do
          def test_method
            ensure_authenticated!
            get("/test/endpoint")
          end
        end

        unauthenticated_service = service_class.new(unauthenticated_client)

        # When attempting authenticated request
        # Then it should fail before making HTTP call
        expect(unauthenticated_client).not_to receive(:get)
        expect { unauthenticated_service.test_method }.to raise_error(Ibkr::AuthenticationError)
      end
    end

    context "when building account-specific service methods" do
      it "combines account path building with HTTP requests" do
        # Given a service that makes account-specific requests
        service_class = Class.new(described_class) do
          def get_account_summary
            path = account_path("/summary")
            get(path)
          end
        end

        account_service = service_class.new(mock_client)
        allow(mock_client).to receive(:account_id).and_return("DU123456")

        # When making account-specific request
        expect(mock_client).to receive(:get).with("/v1/api/portfolio/DU123456/summary")
        account_service.get_account_summary

        # Then it should use properly constructed account path
      end
    end

    context "when transforming API responses to models" do
      it "combines HTTP requests with response transformation" do
        # Given a service that transforms responses
        service_class = Class.new(described_class) do
          def get_transformed_data(model_class)
            response = get("/api/data")
            transform_response(response, model_class)
          end
        end

        transforming_service = service_class.new(mock_client)
        api_response = [{"id" => 1, "name" => "test"}]
        allow(mock_client).to receive(:get).with("/api/data").and_return(api_response)

        # When making request with transformation
        result = transforming_service.get_transformed_data(mock_model_class)

        # Then it should return transformed models
        expect(result).to be_an(Array)
        expect(result.first).to be_a(mock_model_class)
        expect(result.first.data).to eq(api_response.first)
      end
    end
  end

  describe "error handling patterns" do
    context "when HTTP requests fail" do
      it "propagates client HTTP errors" do
        # Given a client that raises HTTP errors
        http_error = StandardError.new("HTTP request failed")
        allow(mock_client).to receive(:get).and_raise(http_error)

        # When making request through service
        # Then it should propagate the error
        expect { service.send(:get, "/api/test") }.to raise_error(StandardError, "HTTP request failed")
      end
    end

    context "when account ID is missing" do
      it "handles missing account ID in path building" do
        # Given a client without account ID
        allow(mock_client).to receive(:account_id).and_return(nil)

        # When building account path
        path = service.send(:account_path, "/summary")

        # Then it should handle nil gracefully
        expect(path).to eq("/v1/api/portfolio//summary")
      end
    end
  end

  describe "method visibility and encapsulation" do
    it "keeps HTTP delegation methods protected" do
      # Given a service instance
      # When checking method visibility
      # Then HTTP methods should be protected
      expect(service.protected_methods).to include(:get, :post, :put, :delete)
    end

    it "keeps authentication helper protected" do
      # Given a service instance
      # When checking method visibility
      # Then authentication helper should be protected
      expect(service.protected_methods).to include(:ensure_authenticated!)
    end

    it "keeps account ID accessor protected" do
      # Given a service instance
      # When checking method visibility
      # Then account ID accessor should be protected
      expect(service.protected_methods).to include(:account_id)
    end

    it "keeps transformation helper protected" do
      # Given a service instance
      # When checking method visibility
      # Then transformation helper should be protected
      expect(service.protected_methods).to include(:transform_response)
    end

    it "keeps path building helpers protected" do
      # Given a service instance
      # When checking method visibility
      # Then path builders should be protected
      expect(service.protected_methods).to include(:account_path, :api_path)
    end

    it "exposes client as public attribute reader" do
      # Given a service instance
      # When checking public methods
      # Then client should be publicly accessible
      expect(service.public_methods).to include(:client)
    end
  end
end
