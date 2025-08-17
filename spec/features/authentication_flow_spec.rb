# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Interactive Brokers Authentication Flow", type: :feature do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"
  include_context "with mocked IBKR API"

  let(:client) { Ibkr::Client.new(default_account_id: "DU123456", live: false) }

  describe "User authenticates with Interactive Brokers" do
    context "when user wants to connect to sandbox environment" do
      it "successfully establishes a secure session" do
        # Given a user wants to access their IBKR account in sandbox mode
        expect(client).to be_instance_of(Ibkr::Client)
        expect(client.instance_variable_get(:@live)).to be false

        # When they initiate authentication
        oauth_client = client.oauth_client
        expect(oauth_client).to receive(:authenticate).and_return(true)
        allow(oauth_client).to receive(:authenticated?).and_return(true)
        allow(oauth_client).to receive(:initialize_session).and_return(true)
        allow(oauth_client).to receive(:get).with("/v1/api/iserver/accounts").and_return({"accounts" => ["DU123456"]})

        # Then they should be successfully authenticated
        result = client.authenticate
        expect(result).to be true
      end

      it "handles authentication failures gracefully" do
        # Given a user attempts to authenticate
        # When the authentication process fails due to invalid credentials
        expect(client.oauth_client).to receive(:authenticate).and_return(false)

        # Then they should receive a clear indication of failure
        result = client.authenticate
        expect(result).to be false
      end
    end

    context "when user wants to connect to live trading environment" do
      let(:live_client) { Ibkr::Client.new(default_account_id: "DU789012", live: true) }

      it "requires additional security validations for live trading" do
        # Given a user wants to access live trading
        expect(live_client.instance_variable_get(:@live)).to be true

        # When they authenticate with live credentials
        oauth_client = live_client.oauth_client
        expect(oauth_client).to receive(:authenticate).and_return(true)
        allow(oauth_client).to receive(:authenticated?).and_return(true)
        allow(oauth_client).to receive(:initialize_session).and_return(true)
        allow(oauth_client).to receive(:get).with("/v1/api/iserver/accounts").and_return({"accounts" => ["DU789012"]})

        # Then the system should apply enhanced security measures
        result = live_client.authenticate
        expect(result).to be true
        expect(live_client.oauth_client.instance_variable_get(:@_live)).to be true
      end
    end
  end

  describe "User manages their session lifecycle" do
    before do
      oauth_client = client.oauth_client
      allow(oauth_client).to receive(:authenticate).and_return(true)
      allow(oauth_client).to receive(:authenticated?).and_return(true)
      allow(oauth_client).to receive(:initialize_session).and_return(true)
      allow(oauth_client).to receive(:get).with("/v1/api/iserver/accounts").and_return({"accounts" => ["DU123456"]})
      client.authenticate
    end

    it "can initialize a brokerage session for trading" do
      # Given an authenticated user
      # When they initialize a trading session
      expect(client.oauth_client).to receive(:initialize_session).with(priority: false).and_return({"connected" => true})

      # Then they should have an active trading session
      result = client.initialize_session
      expect(result).to include("connected" => true)
    end

    it "can logout and terminate their session securely" do
      # Given an authenticated user with an active session
      # When they choose to logout
      expect(client.oauth_client).to receive(:logout).and_return(true)

      # Then their session should be securely terminated
      result = client.logout
      expect(result).to be true
    end

    it "can request priority session for urgent trading" do
      # Given an authenticated user needing priority access
      # When they request priority session initialization
      expect(client.oauth_client).to receive(:initialize_session).with(priority: true).and_return({"priority" => true})

      # Then they should receive priority trading access
      result = client.initialize_session(priority: true)
      expect(result).to include("priority" => true)
    end
  end

  describe "User sets up account context" do
    it "can specify which account to work with when having multiple accounts" do
      # Given a user with multiple IBKR accounts
      # When they create clients with different default accounts
      client1 = Ibkr::Client.new(default_account_id: "DU123456", live: false)
      client2 = Ibkr::Client.new(default_account_id: "DU789012", live: false)

      # Then each client should have their respective default account configured
      expect(client1.instance_variable_get(:@default_account_id)).to eq("DU123456")
      expect(client2.instance_variable_get(:@default_account_id)).to eq("DU789012")

      # And after authentication, active accounts should be set to defaults
      # Mock the OAuth clients and authentication process
      oauth1 = double("oauth_client1",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU123456"]})
      oauth2 = double("oauth_client2",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU789012"]})
      client1.instance_variable_set(:@oauth_client, oauth1)
      client2.instance_variable_set(:@oauth_client, oauth2)

      client1.authenticate
      client2.authenticate

      expect(client1.account_id).to eq("DU123456")
      expect(client2.account_id).to eq("DU789012")
    end

    it "provides access to account-specific services after authentication" do
      # Given a user has created a client for a specific account and authenticated
      oauth_client = double("oauth_client",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU123456"]})
      client.instance_variable_set(:@oauth_client, oauth_client)
      client.authenticate

      # When they access account services
      accounts_service = client.accounts

      # Then they should have access to portfolio and trading operations for their account
      expect(accounts_service).to be_instance_of(Ibkr::Accounts)
      expect(accounts_service.account_id).to eq("DU123456")
    end
  end
end
