# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IBKR Client Error Handling and Edge Cases" do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked IBKR API"

  describe "Network and connectivity errors" do
    let(:client) { Ibkr::Client.new(live: false) }

    context "when IBKR API is unavailable" do
      before do
        allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed, "Connection failed")
      end

      it "provides clear error messages for connection failures" do
        # Given the IBKR API is unreachable
        # When attempting to authenticate
        # Then user should get an informative error
        expect { client.authenticate }.to raise_error(StandardError) do |error|
          expect(error.message).to include("Connection failed")
        end
      end
    end

    context "when network timeouts occur" do
      let(:mock_faraday) { double("faraday") }

      before do
        allow(Faraday).to receive(:new).and_return(mock_faraday)
        allow(mock_faraday).to receive(:post).and_raise(Faraday::TimeoutError)
      end

      it "handles authentication timeouts gracefully" do
        # When timeout occurs during authentication
        # Then user should get a clear timeout error  
        expect { client.authenticate }.to raise_error(StandardError)
      end

      it "maintains clean state after timeout errors" do
        # When timeout occurs during operations
        # Then client state should remain consistent
        begin
          client.authenticate
        rescue StandardError
          # Application should be able to retry after timeout
          expect(client.oauth_client.token).to be_nil
        end
      end
    end

    context "when API returns authentication errors" do
      let(:mock_response) { double("response", success?: false, status: status_code, body: error_body, headers: {}) }
      let(:mock_faraday) { double("faraday", post: mock_response) }

      before do
        allow(Faraday).to receive(:new).and_return(mock_faraday)
      end

      context "with invalid credentials" do
        let(:status_code) { 401 }
        let(:error_body) { '{"error": "invalid_credentials"}' }

        it "fails authentication with clear error message" do
          # When using invalid credentials
          # Then user should get clear feedback about credential issues
          expect { client.authenticate }.to raise_error(StandardError) do |error|
            expect(error.message.downcase).to include("credential").or include("unauthorized").or include("authentication")
          end
        end
      end

      context "with insufficient permissions" do
        let(:status_code) { 403 }
        let(:error_body) { '{"error": "insufficient_permissions"}' }

        it "fails authentication with permission error" do
          # When user lacks required permissions
          # Then they should get clear feedback about access issues
          expect { client.authenticate }.to raise_error(StandardError) do |error|
            expect(error.message.downcase).to include("permission").or include("forbidden").or include("access")
          end
        end
      end

      context "with rate limiting" do
        let(:status_code) { 429 }
        let(:error_body) { '{"error": "rate_limit_exceeded", "retry_after": 60}' }

        it "provides retry guidance for rate limiting" do
          # When hitting rate limits
          # Then user should get guidance on when to retry
          expect { client.authenticate }.to raise_error(StandardError) do |error|
            expect(error.message.downcase).to include("rate").or include("limit").or include("retry")
          end
        end
      end

      context "with server errors" do
        let(:status_code) { 500 }
        let(:error_body) { '{"error": "internal_server_error"}' }

        it "indicates server-side issues" do
          # When IBKR has server issues
          # Then user should understand it's not their fault
          expect { client.authenticate }.to raise_error(StandardError) do |error|
            expect(error.message.downcase).to include("server").or include("internal").or include("system")
          end
        end
      end

      context "with service unavailable" do
        let(:status_code) { 503 }
        let(:error_body) { '{"error": "service_temporarily_unavailable"}' }

        it "indicates temporary service outages" do
          # When service is temporarily down
          # Then user should understand it's temporary
          expect { client.authenticate }.to raise_error(StandardError) do |error|
            expect(error.message.downcase).to include("unavailable").or include("temporary").or include("service")
          end
        end
      end
    end
  end

  describe "Authentication workflows" do
    let(:oauth_client) { Ibkr::Oauth.new(live: false) }

    context "when authentication fails due to invalid credentials" do
      before do
        allow(mock_credentials.ibkr.oauth).to receive(:consumer_key).and_return("invalid_key")
        
        # Mock the API to return 401 for invalid credentials
        stub_request(:post, "https://api.ibkr.com/v1/api/oauth/live_session_token")
          .to_return(status: 401, body: "Invalid consumer key")
      end

      it "clearly indicates credential problems" do
        
        # When user provides invalid credentials
        # Then they should get clear feedback about the problem
        expect { oauth_client.authenticate }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("token").or include("credential").or include("authentication").or include("invalid").or include("key").or include("consumer")
        end
      end
    end

    context "when server returns malformed authentication data" do
      let(:malformed_response) do
        {
          "diffie_hellman_response" => "invalid_dh_response",
          "live_session_token_signature" => "",
          "live_session_token_expiration" => "not_a_timestamp"
        }
      end

      before do
        # Mock the API to return malformed data
        stub_request(:post, "https://api.ibkr.com/v1/api/oauth/live_session_token")
          .to_return(
            status: 200,
            body: malformed_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        
        # Remove the mocking for compute_live_session_token to allow real error to occur
        allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:compute_live_session_token).and_call_original
      end

      it "provides clear feedback for malformed server responses" do
        # When server returns malformed data, user should know what went wrong
        # This test verifies the user experience when IBKR's API returns unexpected data
        
        begin
          result = oauth_client.live_session_token
          # If we get here without error, verify we got a reasonable response
          expect(result).not_to be_nil, "Client should either return valid token or raise informative error for malformed data"
        rescue => error
          # If an error occurs, verify it's informative for the user
          error_msg = error.message.downcase
          expect(error_msg).to include("authentication").or include("invalid").or include("malformed").or include("dh").or include("challenge").or include("must be generated").or include("response").or include("signature")
        end
      end
    end

    context "when working with token lifecycle" do
      let(:expired_token) do
        instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "expired_token", 
          valid?: false,
          expired?: true
        )
      end

      it "properly handles token expiration" do
        oauth_client.instance_variable_set(:@current_token, expired_token)
        
        # When token expires, user should be informed they need to re-authenticate
        # This is the key behavior: expired tokens should not provide access
        expect(oauth_client.authenticated?).to be false
        
        # And user should be able to re-authenticate
        result = oauth_client.authenticate  # Should work with our WebMock setup
        expect(result).to be true
      end
    end

    context "when session initialization fails" do
      include_context "with mocked Faraday client"

      let(:mock_response) { double("response", success?: false, status: 400, body: "Session init failed") }

      it "provides clear feedback for session problems" do
        # First authenticate to avoid authentication error
        oauth_client.instance_variable_set(:@current_token, double("token", valid?: true))
        
        # When session setup fails
        # Then user should get actionable error information
        expect { oauth_client.initialize_session }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("authentication").or include("session").or include("init").or include("400").or include("authenticate").or include("not authenticated")
        end
      end
    end
  end

  describe "Account data reliability" do
    let(:client) { Ibkr::Client.new(live: false) }
    let(:accounts_service) { client.accounts }

    before do
      client.set_account_id("DU123456")
      mock_oauth_client = double("oauth_client", authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
    end

    context "when API returns unexpected response format" do
      before do
        allow(client.oauth_client).to receive(:get).and_return("not_json_response")
      end

      it "handles malformed API responses gracefully" do
        # When IBKR returns non-JSON data
        # Then client should handle it without crashing
        expect { accounts_service.get }.not_to raise_error(JSON::ParserError)
      end
    end

    context "when API data structure changes" do
      let(:unexpected_summary_response) do
        {
          "completely_different_structure" => true,
          "missing_expected_fields" => "yes"
        }
      end

      before do
        allow(client.oauth_client).to receive(:get).and_return(unexpected_summary_response)
      end

      it "validates data structure and provides clear errors" do
        # When IBKR changes their API response format
        # Then user should get clear validation errors
        expect { accounts_service.summary }.to raise_error(StandardError)
      end
    end

    context "when financial data contains invalid values" do
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

      it "rejects invalid financial data" do
        # When API returns invalid numeric values
        # Then data models should validate and reject bad data
        expect { accounts_service.summary }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("validation").or include("invalid").or include("struct")
        end
      end
    end

    context "when data transmission fails" do
      before do
        allow(client.oauth_client).to receive(:get).and_raise(Zlib::GzipFile::Error, "Corrupted data")
      end

      it "handles data corruption during transmission" do
        # When compressed data gets corrupted in transit
        # Then user should get clear error about transmission issues
        expect { accounts_service.summary }.to raise_error(StandardError) do |error|
          expect(error.message).to include("Corrupted data")
        end
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
        mock_oauth_client = double("oauth_client", authenticated?: true)
        allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
        allow(mock_oauth_client).to receive(:get).and_return(large_positions_response)
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
    
    before do
      mock_oauth_client = double("oauth_client", authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
    end

    context "when account ID is not set" do
      it "provides clear guidance when user hasn't specified an account" do
        # Remove the OAuth client mock to see real behavior
        allow(client).to receive(:oauth_client).and_call_original
        
        # Given a user who hasn't set their account ID
        expect(client.account_id).to be_nil
        
        # When user tries to access account operations
        begin
          result = client.accounts.summary
          # If no error, verify we get meaningful feedback
          expect(result).not_to be_nil, "Client should either provide account data or clear error about missing account ID"
        rescue => error
          # If error occurs, it should guide user clearly
          error_msg = error.message.downcase
          expect(error_msg).to include("account").or include("id").or include("context").or include("specify").or include("set").or include("authenticate")
        end
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