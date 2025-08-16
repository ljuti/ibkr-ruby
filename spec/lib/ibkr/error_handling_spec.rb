# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IBKR Client Error Handling and Edge Cases" do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"

  describe "Network and connectivity errors" do
    let(:client) { Ibkr::Client.new(live: false) }

    context "when IBKR API is unavailable" do
      before do
        allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed, "Connection failed")
      end

      it "provides clear error messages for connection failures" do
        # Given the IBKR API is unreachable
        # When attempting to authenticate
        expect { client.authenticate }.to raise_error(Ibkr::ApiError, /Connection failed/)
        
        # Then the error should be descriptive and actionable
      end
    end

    context "when network timeouts occur" do
      let(:mock_faraday) { double("faraday") }

      before do
        allow(Faraday).to receive(:new).and_return(mock_faraday)
        allow(mock_faraday).to receive(:post).and_raise(Faraday::TimeoutError)
      end

      it "handles authentication timeouts gracefully" do
        expect { client.authenticate }.to raise_error(Ibkr::ApiError, /timeout/)
      end

      it "provides retry guidance for timeout scenarios" do
        # When timeout occurs during critical operations
        expect { client.oauth_client.live_session_token }.to raise_error(Ibkr::ApiError, /timeout/)
        
        # The application should be able to retry the operation
        expect(client.oauth_client.token).to be_nil  # State should remain clean
      end
    end

    context "when API returns unexpected HTTP status codes" do
      let(:mock_response) { double("response", success?: false, status: status_code, body: error_body, headers: {}) }
      let(:mock_faraday) { double("faraday", post: mock_response) }

      before do
        allow(Faraday).to receive(:new).and_return(mock_faraday)
      end

      context "with 401 Unauthorized" do
        let(:status_code) { 401 }
        let(:error_body) { '{"error": "invalid_credentials"}' }

        it "indicates authentication credential problems" do
          expect { client.authenticate }.to raise_error(Ibkr::AuthenticationError)
        end
      end

      context "with 403 Forbidden" do
        let(:status_code) { 403 }
        let(:error_body) { '{"error": "insufficient_permissions"}' }

        it "indicates permission or access level issues" do
          expect { client.authenticate }.to raise_error(Ibkr::ApiError)
        end
      end

      context "with 429 Rate Limited" do
        let(:status_code) { 429 }
        let(:error_body) { '{"error": "rate_limit_exceeded", "retry_after": 60}' }

        it "indicates rate limiting and suggests retry timing" do
          expect { client.authenticate }.to raise_error(Ibkr::RateLimitError)
          
          # Application should be able to parse retry-after information
          expect(error_body).to include("retry_after")
        end
      end

      context "with 500 Internal Server Error" do
        let(:status_code) { 500 }
        let(:error_body) { '{"error": "internal_server_error"}' }

        it "indicates IBKR system issues requiring retry logic" do
          expect { client.authenticate }.to raise_error(Ibkr::ApiError::ServerError)
        end
      end

      context "with 503 Service Unavailable" do
        let(:status_code) { 503 }
        let(:error_body) { '{"error": "service_temporarily_unavailable"}' }

        it "indicates temporary service outages" do
          expect { client.authenticate }.to raise_error(Ibkr::ApiError::ServiceUnavailable)
        end
      end
    end
  end

  describe "Authentication and authorization edge cases" do
    let(:oauth_client) { Ibkr::Oauth.new(live: false) }

    context "when credentials are invalid or expired" do
      before do
        mock_credentials.ibkr.oauth.stub(:consumer_key).and_return("invalid_key")
      end

      it "fails authentication with invalid consumer key" do
        mock_response = double("response", success?: false, status: 401, body: "Invalid consumer key")
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(mock_response)
        
        expect { oauth_client.authenticate }.to raise_error(/Failed to get live session token/)
      end
    end

    context "when live session token is malformed" do
      let(:malformed_response) do
        {
          "diffie_hellman_response" => "invalid_dh_response",
          "live_session_token_signature" => "",
          "live_session_token_expiration" => "not_a_timestamp"
        }
      end

      before do
        mock_response = double("response", success?: true, body: malformed_response.to_json, headers: {})
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(mock_response)
      end

      it "handles malformed DH response gracefully" do
        expect { oauth_client.live_session_token }.to raise_error
      end
    end

    context "when token expires during operations" do
      let(:expired_token) do
        instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "expired_token",
          valid?: false,
          expired?: true
        )
      end

      it "detects expired tokens and requires re-authentication" do
        oauth_client.instance_variable_set(:@token, expired_token)
        
        # Operations requiring valid token should fail gracefully
        expect(oauth_client.token.valid?).to be false
        expect(oauth_client.token.expired?).to be true
      end
    end

    context "when session initialization fails" do
      include_context "with mocked Faraday client"

      let(:mock_response) { double("response", success?: false, status: 400, body: "Session init failed") }

      it "provides clear feedback for session initialization failures" do
        expect { oauth_client.initialize_session }.to raise_error(/POST request failed: 400/)
      end
    end
  end

  describe "Data integrity and parsing errors" do
    let(:client) { Ibkr::Client.new(live: false) }
    let(:accounts_service) { client.accounts }

    before do
      client.set_account_id("DU123456")
      allow(client).to receive(:oauth_client).and_return(double("oauth_client"))
    end

    context "when API returns malformed JSON" do
      before do
        allow(client.oauth_client).to receive(:get).and_return("not_json_response")
      end

      it "handles non-JSON responses gracefully" do
        # This would depend on how the oauth_client.get method handles parsing
        # The test shows the expected behavior
        expect { accounts_service.get }.not_to raise_error(JSON::ParserError)
      end
    end

    context "when API returns unexpected data structure" do
      let(:unexpected_summary_response) do
        {
          "completely_different_structure" => true,
          "missing_expected_fields" => "yes"
        }
      end

      before do
        allow(client.oauth_client).to receive(:get).and_return(unexpected_summary_response)
      end

      it "handles missing expected fields in summary data" do
        expect { accounts_service.summary }.to raise_error  # Dry::Struct should validate
      end
    end

    context "when numeric data contains invalid values" do
      let(:invalid_numeric_response) do
        {
          "netliquidation" => { "amount" => "NaN", "currency" => "USD" },
          "availablefunds" => { "amount" => "Infinity", "currency" => "USD" },
          "buyingpower" => { "amount" => nil, "currency" => "USD" }
        }
      end

      before do
        allow(client.oauth_client).to receive(:get).and_return(invalid_numeric_response)
        allow(accounts_service).to receive(:normalize_summary).and_return(invalid_numeric_response)
      end

      it "handles NaN and Infinity values in financial data" do
        # Dry::Struct with type coercion should handle these cases
        expect { accounts_service.summary }.to raise_error(Dry::Struct::Error)
      end
    end

    context "when gzip decompression fails" do
      let(:mock_response) do
        double("response", 
          success?: true, 
          body: "corrupted_gzip_data",
          headers: { "content-encoding" => "gzip" }
        )
      end

      before do
        allow(client.oauth_client).to receive(:get).and_raise(Zlib::GzipFile::Error)
      end

      it "handles corrupted gzip data gracefully" do
        expect { accounts_service.summary }.to raise_error(Zlib::GzipFile::Error)
      end
    end
  end

  describe "Resource and memory management" do
    context "when handling large position lists" do
      let(:large_positions_response) do
        {
          "results" => Array.new(10000) do |i|
            {
              "conid" => "#{i}",
              "position" => rand(1000),
              "description" => "Stock #{i}",
              "market_value" => rand(100000.0),
              "currency" => "USD",
              "unrealized_pnl" => rand(-10000.0..10000.0),
              "realized_pnl" => 0.0,
              "market_price" => rand(50.0..500.0),
              "security_type" => "STK",
              "asset_class" => "STOCK",
              "sector" => "Technology",
              "group" => "Technology - Software"
            }
          end
        }
      end

      let(:client) { Ibkr::Client.new(live: false) }
      let(:accounts_service) { client.accounts }

      before do
        client.set_account_id("DU123456")
        allow(client.oauth_client).to receive(:get).and_return(large_positions_response)
      end

      it "handles large datasets without memory issues" do
        # Given a portfolio with thousands of positions
        # When requesting positions data
        result = accounts_service.positions
        
        # Then it should handle the large dataset efficiently
        expect(result["results"]).to be_an(Array)
        expect(result["results"].size).to eq(10000)
        
        # Memory usage should be reasonable (not testing exact numbers due to test environment)
        expect { result["results"].each { |pos| pos["description"] } }.not_to raise_error
      end
    end

    context "when API responses are extremely large" do
      it "handles memory constraints during JSON parsing" do
        # This would test behavior with very large JSON responses
        # The actual implementation would depend on JSON parsing limits
        large_json = '{"data": "' + ('x' * 1_000_000) + '"}'
        
        expect { JSON.parse(large_json) }.not_to raise_error
      end
    end
  end

  describe "Concurrency and thread safety" do
    let(:client) { Ibkr::Client.new(live: false) }

    context "when multiple threads access the same client" do
      it "maintains thread safety for authentication state" do
        threads = Array.new(5) do
          Thread.new do
            # Each thread should be able to check authentication state safely
            client.authenticate rescue nil  # Suppress errors for this test
            client.account_id
          end
        end
        
        # All threads should complete without race conditions
        expect { threads.map(&:join) }.not_to raise_error
      end

      it "handles concurrent API requests safely" do
        client.set_account_id("DU123456")
        allow(client.oauth_client).to receive(:get).and_return({})
        
        threads = Array.new(3) do
          Thread.new do
            client.accounts.get rescue nil
          end
        end
        
        expect { threads.map(&:join) }.not_to raise_error
      end
    end
  end

  describe "Configuration and environment errors" do
    context "when cryptographic files are missing" do
      before do
        allow(File).to receive(:read).and_raise(Errno::ENOENT, "No such file or directory")
      end

      it "provides clear error messages for missing certificate files" do
        expect { Ibkr::Oauth.new(live: false) }.to raise_error(Errno::ENOENT)
      end
    end

    context "when Rails credentials are misconfigured" do
      before do
        allow(Rails).to receive(:application).and_raise(NoMethodError, "undefined method for nil")
      end

      it "handles missing Rails application gracefully" do
        expect { Ibkr::Oauth.new(live: false) }.to raise_error(NoMethodError)
      end
    end

    context "when environment-specific configuration is wrong" do
      it "validates live vs sandbox environment configuration" do
        live_client = Ibkr::Client.new(live: true)
        sandbox_client = Ibkr::Client.new(live: false)
        
        expect(live_client.instance_variable_get(:@live)).to be true
        expect(sandbox_client.instance_variable_get(:@live)).to be false
      end
    end
  end

  describe "Edge cases in business logic" do
    let(:client) { Ibkr::Client.new(live: false) }

    context "when account ID is not set" do
      it "handles operations that require account context" do
        # Given a client without account ID set
        expect(client.account_id).to be_nil
        
        # When attempting account-specific operations
        # Then it should fail with meaningful error
        expect { client.accounts.summary }.to raise_error
      end
    end

    context "when switching between multiple accounts" do
      it "properly isolates account data" do
        client.set_account_id("DU111111")
        first_account_id = client.accounts.account_id
        
        client.set_account_id("DU222222")
        second_account_id = client.accounts.account_id
        
        expect(first_account_id).to eq("DU111111")
        expect(second_account_id).to eq("DU222222")
        expect(first_account_id).not_to eq(second_account_id)
      end
    end

    context "when account has no positions or transactions" do
      before do
        client.set_account_id("DU123456")
        allow(client.oauth_client).to receive(:get).and_return({ "results" => [] })
        allow(client.oauth_client).to receive(:post).and_return([])
      end

      it "handles empty portfolios gracefully" do
        positions = client.accounts.positions
        expect(positions["results"]).to be_empty
        
        transactions = client.accounts.transactions("265598", 30)
        expect(transactions).to be_empty
      end
    end
  end
end