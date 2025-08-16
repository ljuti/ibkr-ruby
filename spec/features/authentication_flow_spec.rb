# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Interactive Brokers Authentication Flow", type: :feature do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"

  let(:client) { Ibkr::Client.new(live: false) }

  describe "User authenticates with Interactive Brokers" do
    context "when user wants to connect to sandbox environment" do
      it "successfully establishes a secure session" do
        # Given a user wants to access their IBKR account in sandbox mode
        expect(client).to be_instance_of(Ibkr::Client)
        expect(client.instance_variable_get(:@live)).to be false

        # When they initiate authentication
        expect(client.oauth_client).to receive(:authenticate).and_return(true)
        
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
      let(:live_client) { Ibkr::Client.new(live: true) }

      it "requires additional security validations for live trading" do
        # Given a user wants to access live trading
        expect(live_client.instance_variable_get(:@live)).to be true
        
        # When they authenticate with live credentials
        expect(live_client.oauth_client).to receive(:authenticate).and_return(true)
        
        # Then the system should apply enhanced security measures
        result = live_client.authenticate
        expect(result).to be true
        expect(live_client.oauth_client.instance_variable_get(:@_live)).to be true
      end
    end
  end

  describe "User manages their session lifecycle" do
    before do
      allow(client.oauth_client).to receive(:authenticate).and_return(true)
      client.authenticate
    end

    it "can initialize a brokerage session for trading" do
      # Given an authenticated user
      # When they initialize a trading session
      expect(client.oauth_client).to receive(:initialize_session).with(priority: false).and_return({ "connected" => true })
      
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
      expect(client.oauth_client).to receive(:initialize_session).with(priority: true).and_return({ "priority" => true })
      
      # Then they should receive priority trading access
      result = client.initialize_session(priority: true)
      expect(result).to include("priority" => true)
    end
  end

  describe "User sets up account context" do
    it "can specify which account to work with when having multiple accounts" do
      # Given a user with multiple IBKR accounts
      account_id = "DU123456"
      
      # When they specify which account to use
      client.set_account_id(account_id)
      
      # Then the client should use that account for subsequent operations
      expect(client.account_id).to eq(account_id)
    end

    it "provides access to account-specific services after account selection" do
      # Given a user has selected an account
      client.set_account_id("DU123456")
      
      # When they access account services
      accounts_service = client.accounts
      
      # Then they should have access to portfolio and trading operations
      expect(accounts_service).to be_instance_of(Ibkr::Accounts)
      expect(accounts_service.account_id).to eq("DU123456")
    end
  end
end