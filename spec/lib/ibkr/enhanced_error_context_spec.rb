# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Enhanced Error Context" do
  let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }

  before do
    allow_any_instance_of(Ibkr::Oauth).to receive(:authenticated?).and_return(true)
  end

  describe Ibkr::BaseError do
    describe "enhanced context capture" do
      let(:error) do
        Ibkr::BaseError.with_context(
          "Test error message",
          context: {
            endpoint: "/test/endpoint",
            account_id: "DU123456",
            operation: "test_operation"
          }
        )
      end

      it "captures timestamp and version information" do
        expect(error.context[:timestamp]).not_to be_nil
        expect(error.context[:timestamp]).not_to be_empty
        expect(error.context[:ibkr_version]).to eq(Ibkr::VERSION)
        expect(error.context[:thread_id]).not_to be_nil
      end

      it "includes custom context" do
        expect(error.context[:endpoint]).to eq("/test/endpoint")
        expect(error.context[:account_id]).to eq("DU123456")
        expect(error.context[:operation]).to eq("test_operation")
      end

      it "captures caller location" do
        expect(error.context[:caller_location]).to be_an(Array)
        expect(error.context[:caller_location]).not_to be_empty
      end
    end

    describe "suggestions generation" do
      it "provides authentication-specific suggestions for AuthenticationError" do
        error = Ibkr::AuthenticationError.new("Authentication failed")
        suggestions = error.suggestions

        expect(suggestions).to include("Verify your OAuth credentials are correct")
        expect(suggestions).to include("Check if your session has expired")
        expect(suggestions).to include("Ensure your system clock is synchronized")
      end

      it "provides rate limit suggestions for RateLimitError" do
        error = Ibkr::RateLimitError.new("Rate limit exceeded")
        suggestions = error.suggestions

        expect(suggestions).to include("Implement exponential backoff in your retry logic")
        expect(suggestions).to include("Reduce the frequency of API calls")
        expect(suggestions).to include("Consider caching responses to minimize API usage")
      end

      it "provides repository-specific suggestions" do
        error = Ibkr::RepositoryError.new("Repository error")
        suggestions = error.suggestions

        expect(suggestions).to include("Check if the repository type is supported")
        expect(suggestions).to include("Verify the underlying data source is accessible")
        expect(suggestions).to include("Try switching to a different repository implementation")
      end

      it "provides endpoint-specific suggestions" do
        error = Ibkr::BaseError.with_context(
          "Error message",
          context: {endpoint: "/v1/api/iserver/accounts"}
        )
        suggestions = error.suggestions

        expect(suggestions).to include("Ensure you're authenticated before fetching accounts")
        expect(suggestions).to include("Verify your account has proper permissions")
      end

      it "provides account-specific suggestions for empty account ID" do
        error = Ibkr::BaseError.with_context(
          "Error message",
          context: {account_id: ""}
        )
        suggestions = error.suggestions

        expect(suggestions).to include("Provide a valid account ID")
        expect(suggestions).to include("Use client.available_accounts to see available account IDs")
      end
    end

    describe "debug information" do
      let(:response) { double("response", status: 400, headers: {"X-Request-ID" => "12345"}) }
      let(:error) do
        Ibkr::BaseError.new(
          "Test error",
          response: response,
          context: {
            endpoint: "/test/endpoint",
            retry_count: 2
          }
        )
      end

      it "includes debug information" do
        debug_info = error.debug_info

        expect(debug_info[:error_class]).to eq("Ibkr::BaseError")
        expect(debug_info[:http_status]).to eq(400)
        expect(debug_info[:request_id]).to eq("12345")
        expect(debug_info[:endpoint]).to eq("/test/endpoint")
        expect(debug_info[:retry_count]).to eq(2)
      end
    end

    describe "detailed_message" do
      let(:error) do
        Ibkr::AuthenticationError.with_context(
          "Test error",
          context: {
            endpoint: "/test/endpoint",
            account_id: "DU123456",
            retry_count: 3
          }
        )
      end

      it "includes context in detailed message" do
        detailed = error.detailed_message

        expect(detailed).to include("Test error")
        expect(detailed).to include("Endpoint: /test/endpoint")
        expect(detailed).to include("Account: DU123456")
        expect(detailed).to include("Retries attempted: 3")
        expect(detailed).to include("Suggestions:")
      end
    end

    describe "to_h serialization" do
      let(:error) do
        Ibkr::BaseError.with_context(
          "Test error",
          context: {operation: "test"}
        )
      end

      it "includes all enhanced information" do
        hash = error.to_h

        expect(hash[:error]).to eq("Ibkr::BaseError")
        expect(hash[:message]).to eq("Test error")
        expect(hash[:context]).to include(:operation, :timestamp, :ibkr_version)
        expect(hash[:suggestions]).to be_an(Array)
        expect(hash[:debug_info]).to be_a(Hash)
      end
    end
  end

  describe Ibkr::AuthenticationError do
    describe "factory methods with context" do
      it "creates session failed error with context" do
        error = Ibkr::AuthenticationError.session_failed(
          "Session init failed",
          context: {account_id: "DU123456"}
        )

        expect(error).to be_a(Ibkr::AuthenticationError::SessionInitializationFailed)
        expect(error.context[:operation]).to eq("session_init")
        expect(error.context[:account_id]).to eq("DU123456")
      end

      it "creates credentials invalid error with context" do
        error = Ibkr::AuthenticationError.credentials_invalid(
          "Bad credentials",
          context: {username: "test_user"}
        )

        expect(error).to be_a(Ibkr::AuthenticationError::InvalidCredentials)
        expect(error.context[:operation]).to eq("authentication")
        expect(error.context[:username]).to eq("test_user")
      end

      it "creates token expired error with context" do
        error = Ibkr::AuthenticationError.token_expired(
          "Token expired",
          context: {token_age: 3600}
        )

        expect(error).to be_a(Ibkr::AuthenticationError::TokenExpired)
        expect(error.context[:operation]).to eq("token_validation")
        expect(error.context[:token_age]).to eq(3600)
      end
    end

    describe "from_response with context" do
      let(:response) do
        double("response",
          status: 401,
          env: {
            url: double(path: "/oauth/token"),
            request_headers: {"Authorization" => "Bearer token"}
          },
          headers: {"X-Request-ID" => "auth-123"})
      end

      let(:auth_context) { {user_id: "test_user"} }

      before do
        allow(Ibkr::AuthenticationError).to receive(:extract_error_details)
          .and_return({message: "Invalid token", request_id: "auth-123"})
      end

      it "creates error with enhanced authentication context" do
        error = Ibkr::AuthenticationError.from_response(response, context: auth_context)

        expect(error.context[:response_status]).to eq(401)
        expect(error.context[:request_id]).to eq("auth-123")
        expect(error.context[:auth_header_present]).to be true
        expect(error.context[:endpoint]).to eq("/oauth/token")
        expect(error.context[:user_id]).to eq("test_user")
      end
    end
  end

  describe Ibkr::ApiError do
    describe "factory methods with context" do
      it "creates account not found error with context" do
        error = Ibkr::ApiError.account_not_found(
          "DU999999",
          context: {available_accounts: ["DU123456", "DU789012"]}
        )

        expect(error).to be_a(Ibkr::ApiError::NotFound)
        expect(error.message).to include("DU999999")
        expect(error.context[:account_id]).to eq("DU999999")
        expect(error.context[:operation]).to eq("account_lookup")
        expect(error.context[:available_accounts]).to eq(["DU123456", "DU789012"])
      end

      it "creates validation failed error with context" do
        validation_errors = [
          {"field" => "amount", "error" => "must be positive"}
        ]

        error = Ibkr::ApiError.validation_failed(
          validation_errors,
          context: {request_type: "order"}
        )

        expect(error).to be_a(Ibkr::ApiError::ValidationError)
        expect(error.validation_errors).to eq(validation_errors)
        expect(error.context[:operation]).to eq("request_validation")
        expect(error.context[:request_type]).to eq("order")
      end

      it "creates server error with context" do
        error = Ibkr::ApiError.server_error(
          "Database connection failed",
          context: {server_id: "web-01"}
        )

        expect(error).to be_a(Ibkr::ApiError::ServerError)
        expect(error.context[:operation]).to eq("server_request")
        expect(error.context[:server_id]).to eq("web-01")
      end
    end
  end

  describe Ibkr::RepositoryError do
    describe "enhanced factory methods" do
      it "creates unsupported repository type error" do
        error = Ibkr::RepositoryError.unsupported_repository_type(
          "custom",
          context: {client_type: "test"}
        )

        expect(error.message).to include("custom")
        expect(error.context[:repository_type]).to eq("custom")
        expect(error.context[:operation]).to eq("factory_creation")
        expect(error.context[:client_type]).to eq("test")
      end

      it "creates data not found error" do
        error = Ibkr::RepositoryError.data_not_found(
          "Account",
          "DU999999",
          context: {repository_type: "test"}
        )

        expect(error.message).to include("Account")
        expect(error.message).to include("DU999999")
        expect(error.context[:resource]).to eq("Account")
        expect(error.context[:identifier]).to eq("DU999999")
        expect(error.context[:operation]).to eq("data_retrieval")
        expect(error.context[:repository_type]).to eq("test")
      end
    end
  end

  describe "Client error handling integration" do
    let(:oauth_client) { double("oauth_client") }

    before do
      allow(client).to receive(:oauth_client).and_return(oauth_client)
    end

    describe "authentication required error" do
      it "provides enhanced context for authentication errors" do
        # Create a new client for this test
        test_client = Ibkr::Client.new(default_account_id: "DU123456", live: false)

        # Try to set an account when not authenticated should fail
        expect do
          test_client.set_active_account("DU789012")
        end.to raise_error(Ibkr::AuthenticationError) do |error|
          expect(error.context[:operation]).to eq("account_management")
          expect(error.context[:default_account_id]).to eq("DU123456")
          expect(error.suggestions).to include("Verify your OAuth credentials are correct")
        end
      end
    end

    describe "account switching error" do
      before do
        allow(oauth_client).to receive(:authenticated?).and_return(true)
        allow(oauth_client).to receive(:initialize_session).and_return(true)
        allow(oauth_client).to receive(:get).with("/v1/api/iserver/accounts").and_return({"accounts" => ["DU123456", "DU789012"]})
        allow(oauth_client).to receive(:authenticate).and_return(true)
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate
      end

      it "provides enhanced context for account not found" do
        expect do
          client.set_active_account("DU999999")
        end.to raise_error(Ibkr::ApiError::NotFound) do |error|
          expect(error.context[:available_accounts]).to eq(["DU123456", "DU789012"])
          expect(error.context[:operation]).to eq("set_active_account")
          expect(error.suggestions).to include("Use client.available_accounts to see available account IDs")
        end
      end
    end
  end
end
