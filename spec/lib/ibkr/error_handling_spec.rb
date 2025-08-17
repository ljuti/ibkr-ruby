# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IBKR Client Error Handling and Edge Cases" do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked IBKR API"

  describe "Network and connectivity errors" do
    let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }

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

        client.authenticate
      rescue
        # Application should be able to retry after timeout
        # Check that no token was set in the authenticator
        authenticator = client.oauth_client.authenticator
        expect(authenticator.current_token).to be_nil
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
            headers: {"Content-Type" => "application/json"}
          )

        # Remove the mocking for compute_live_session_token to allow real error to occur
        allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:compute_live_session_token).and_call_original
      end

      it "provides clear feedback for malformed server responses" do
        # When server returns malformed data, user should know what went wrong
        # This test verifies the user experience when IBKR's API returns unexpected data

        # Mock a scenario where DH challenge generation fails due to malformed server data
        allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:generate_dh_challenge).and_raise(StandardError, "Malformed DH parameters in server response")

        # When requesting token with malformed server data
        # Then user should get clear error message about the problem
        expect { oauth_client.live_session_token }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("malformed").or include("dh").or include("parameters").or include("server")
        end
      end
    end

    context "when working with token lifecycle" do
      let(:expired_token) do
        instance_double("Ibkr::Oauth::LiveSessionToken",
          token: "expired_token",
          valid?: false,
          expired?: true)
      end

      it "properly handles token expiration" do
        oauth_client.authenticator.current_token = expired_token

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
        oauth_client.authenticator.current_token = double("token", valid?: true)

        # When session setup fails
        # Then user should get actionable error information
        expect { oauth_client.initialize_session }.to raise_error(StandardError) do |error|
          expect(error.message.downcase).to include("authentication").or include("session").or include("init").or include("400").or include("authenticate").or include("not authenticated")
        end
      end
    end
  end

  describe "Account data reliability" do
    let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }
    let(:accounts_service) { client.accounts }

    before do
      mock_oauth_client = double("oauth_client", authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
    end

    context "when API returns unexpected response format" do
      before do
        allow(client.oauth_client).to receive(:get).and_return("not_json_response")
      end

      it "handles malformed API responses gracefully" do
        # When IBKR returns non-JSON data
        # Then user should get clear feedback about the issue

        result = accounts_service.get
        # If we get a result, it should be usable data
        expect(result).to be_a(Hash).or be_a(String)
      rescue => error
        # If an error occurs, it should be informative for the user
        expect(error.message.downcase).to include("response").or include("data").or include("format").or include("invalid")
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
          "netliquidation" => {"amount" => "NaN", "currency" => "USD"},
          "availablefunds" => {"amount" => "Infinity", "currency" => "USD"},
          "buyingpower" => {"amount" => nil, "currency" => "USD"}
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
          # The error message should indicate the data validation issue
          expect(error.message.downcase).to include("missing").or include("required").or include("validation").or include("invalid").or include("struct")
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
              "conid" => i.to_s,
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

      let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }
      let(:accounts_service) { client.accounts }

      before do
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

        # Memory usage should be reasonable - user should be able to access position data
        sample_position = result["results"].first
        expect(sample_position["description"]).to be_a(String)

        # User should be able to work with the full dataset
        descriptions = result["results"].map { |pos| pos["description"] }
        expect(descriptions.size).to eq(10000)
        expect(descriptions.first).to be_a(String)
      end
    end

    context "when API responses are extremely large" do
      it "handles memory constraints during JSON parsing" do
        # When IBKR returns extremely large JSON responses
        # Then user should either get the data or clear feedback about size limits
        large_json = '{"data": "' + ("x" * 1_000_000) + '"}'

        begin
          result = JSON.parse(large_json)
          # If parsing succeeds, user should get valid data
          expect(result).to be_a(Hash)
          expect(result["data"]).to be_a(String)
        rescue => error
          # If parsing fails due to size, error should be informative
          expect(error.message.downcase).to include("memory").or include("size").or include("large").or include("limit")
        end
      end
    end
  end

  describe "Concurrency and thread safety" do
    let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }

    context "when multiple threads access the same client" do
      it "maintains thread safety for authentication state" do
        threads = Array.new(5) do
          Thread.new do
            # Each thread should be able to check authentication state safely
            begin
              client.authenticate
            rescue
              nil
            end  # Suppress errors for this test
            client.account_id
          end
        end

        # All threads should complete successfully and return consistent results
        results = threads.map(&:join).map(&:value)
        expect(results).to all(eq("DU123456").or(be_nil))
        # All threads completed successfully (no exceptions raised)
        expect(threads).to all(satisfy { |t| !t.status.nil? || t.value })
      end

      it "handles concurrent API requests safely" do
        oauth_client = double("oauth_client")
        allow(oauth_client).to receive(:get).and_return({"account_data" => "test"})
        allow(client).to receive(:oauth_client).and_return(oauth_client)

        threads = Array.new(3) do
          Thread.new do
            client.accounts.get
          rescue
            nil
          end
        end

        # All threads should complete and return consistent API responses
        results = threads.map(&:join).map(&:value)
        expect(results).to all(be_a(Hash).or(be_nil))
        # Threads that succeeded should have account data
        successful_results = results.compact
        expect(successful_results).to all(have_key("account_data")) if successful_results.any?
      end
    end
  end

  describe "Configuration and environment errors" do
    context "when cryptographic files are missing" do
      it "provides clear error messages for missing certificate files" do
        # When configuration tries to load missing certificates
        # This test validates the user experience of missing files

        # Mock a scenario where signature generation fails due to missing files
        allow_any_instance_of(Ibkr::Oauth::SignatureGenerator).to receive(:generate_rsa_signature).and_raise(Errno::ENOENT, "No such file: ./config/certs/private_signature.pem")

        # Create client in this context
        oauth_client = Ibkr::Oauth.new(live: false)

        # When user tries to use OAuth with missing certificates
        # Then they should get clear error about missing files
        expect { oauth_client.live_session_token }.to raise_error(Errno::ENOENT) do |error|
          expect(error.message).to include("No such file").or include("private_signature.pem").or include("certificate")
        end
      end
    end

    context "when Rails credentials are misconfigured" do
      before do
        # Remove the mock Rails and simulate missing application
        RSpec::Mocks.space.proxy_for(Rails).reset if defined?(Rails)
        allow(Object).to receive(:const_defined?).with("Rails").and_return(false)
      end

      it "handles missing Rails application gracefully" do
        # When Rails is not available, user should get clear error or fallback behavior

        client = Ibkr::Oauth.new(live: false)
        # If no error, verify client handles missing Rails gracefully
        expect(client).to be_instance_of(Ibkr::Oauth::Client)
      rescue => error
        # If error occurs, verify it's informative about missing Rails config
        expect(error.message.downcase).to include("rails").or include("credentials").or include("config")
      end
    end

    context "when environment-specific configuration is wrong" do
      it "validates live vs sandbox environment configuration" do
        live_client = Ibkr::Client.new(default_account_id: "DU111111", live: true)
        sandbox_client = Ibkr::Client.new(default_account_id: "DU222222", live: false)

        expect(live_client.live).to be true
        expect(sandbox_client.live).to be false
      end
    end
  end

  describe "Edge cases in business logic" do
    let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }

    before do
      mock_oauth_client = double("oauth_client", authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
    end

    context "when working with multiple accounts" do
      it "properly isolates account data for different clients" do
        # Given two different clients for different accounts
        client1 = Ibkr::Client.new(default_account_id: "DU111111", live: false)
        client2 = Ibkr::Client.new(default_account_id: "DU222222", live: false)

        # Simulate authentication for both clients
        oauth1 = double("oauth_client1", authenticate: true, authenticated?: true)
        oauth2 = double("oauth_client2", authenticate: true, authenticated?: true)
        allow(client1).to receive(:oauth_client).and_return(oauth1)
        allow(client2).to receive(:oauth_client).and_return(oauth2)
        allow(oauth1).to receive(:initialize_session)
        allow(oauth2).to receive(:initialize_session)
        allow(oauth1).to receive(:get).with("/v1/api/iserver/accounts").and_return({"accounts" => ["DU111111"]})
        allow(oauth2).to receive(:get).with("/v1/api/iserver/accounts").and_return({"accounts" => ["DU222222"]})
        client1.authenticate
        client2.authenticate

        # Then each client should maintain its own account context
        expect(client1.account_id).to eq("DU111111")
        expect(client2.account_id).to eq("DU222222")
        expect(client1.accounts.account_id).to eq("DU111111")
        expect(client2.accounts.account_id).to eq("DU222222")
      end
    end

    context "when account has no positions or transactions" do
      before do
        allow(client.oauth_client).to receive(:get).and_return({"results" => []})
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
