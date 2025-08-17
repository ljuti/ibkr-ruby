# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Fetch Available Accounts Integration", type: :unit do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked IBKR API"

  let(:client) { Ibkr::Client.new(live: false) }

  describe "fetch_available_accounts integration" do
    it "fetches accounts from IBKR API after session initialization" do
      # Given an authenticated client
      client.authenticate
      
      # When fetch_available_accounts is called (internally)
      # It should make the correct API calls
      expect(client.available_accounts).to eq(["DU123456"])
      expect(client.active_account_id).to eq("DU123456")
    end

    it "handles accounts endpoint response properly" do
      # Given an authenticated client
      client.authenticate
      
      # When we check the response structure
      # The accounts should be extracted from the complex IBKR response
      expect(client.available_accounts).to be_an(Array)
      expect(client.available_accounts).not_to be_empty
      expect(client.available_accounts.first).to match(/^DU\d+$/)
    end

    context "with multiple accounts" do
      before do
        # Mock a multiple accounts response
        accounts_response = {
          "accounts" => ["DU123456", "DU789012"],
          "acctProps" => {
            "DU123456" => {"hasChildAccounts" => false},
            "DU789012" => {"hasChildAccounts" => false}
          },
          "selectedAccount" => "DU123456"
        }
        
        stub_request(:get, "#{base_url}/v1/api/iserver/accounts")
          .to_return(
            status: 200,
            body: accounts_response.to_json,
            headers: {"Content-Type" => "application/json"}
          )
      end

      it "extracts all available account IDs" do
        client.authenticate
        
        expect(client.available_accounts).to eq(["DU123456", "DU789012"])
        expect(client.active_account_id).to eq("DU123456")  # First account becomes active
      end
    end

    context "when session initialization is required" do
      it "calls initialize_session before fetching accounts" do
        oauth_client = client.oauth_client
        expect(oauth_client).to receive(:initialize_session).with(priority: true).once
        
        client.authenticate
      end
    end

    context "when authentication fails" do
      it "raises AuthenticationError if not authenticated" do
        unauthenticated_client = Ibkr::Client.new(live: false)
        oauth_client = double("oauth_client", authenticated?: false)
        unauthenticated_client.instance_variable_set(:@oauth_client, oauth_client)
        
        expect {
          unauthenticated_client.send(:fetch_available_accounts)
        }.to raise_error(Ibkr::AuthenticationError, /Client must be authenticated/)
      end
    end

    context "when API call fails" do
      before do
        stub_request(:get, "#{base_url}/v1/api/iserver/accounts")
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "raises ServerError for server failures" do
        expect {
          client.authenticate
        }.to raise_error(Ibkr::ApiError::ServerError, /Internal Server Error/)
      end
    end
  end
end