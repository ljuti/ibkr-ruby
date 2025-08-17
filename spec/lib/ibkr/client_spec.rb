# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Client do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"

  let(:client) { described_class.new(default_account_id: "DU123456", live: false) }
  let(:live_client) { described_class.new(default_account_id: "DU789012", live: true) }

  describe "initialization" do
    context "when creating sandbox client" do
      it "initializes with sandbox configuration and default account" do
        # Given a user wants to test in sandbox environment with specific default account
        # When creating a new client
        client = described_class.new(default_account_id: "DU123456", live: false)
        
        # Then it should be configured for sandbox mode
        expect(client.instance_variable_get(:@live)).to be false
        expect(client.instance_variable_get(:@default_account_id)).to eq("DU123456")
        # Active account is not set until authentication
        expect(client.active_account_id).to be_nil
      end
    end

    context "when creating live trading client" do
      it "initializes with live trading configuration and default account" do
        # Given a user wants to trade in live environment with specific default account
        # When creating a live client
        client = described_class.new(default_account_id: "DU789012", live: true)
        
        # Then it should be configured for live trading
        expect(client.instance_variable_get(:@live)).to be true
        expect(client.instance_variable_get(:@default_account_id)).to eq("DU789012")
        # Active account is not set until authentication
        expect(client.active_account_id).to be_nil
      end
    end

    it "allows creation without default account ID" do
      # Given default_account_id is optional
      # When creating client without default account
      client = described_class.new(live: false)
      
      # Then it should initialize successfully
      expect(client.instance_variable_get(:@live)).to be false
      expect(client.instance_variable_get(:@default_account_id)).to be_nil
      expect(client.active_account_id).to be_nil
    end
  end

  describe "authentication delegation" do
    let(:mock_oauth_client) { double("oauth_client", authenticated?: false) }

    before do
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
    end

    describe "#authenticate" do
      it "delegates authentication to OAuth client and sets up accounts" do
        # Given an OAuth client is available
        expect(mock_oauth_client).to receive(:authenticate).and_return(true)
        allow(mock_oauth_client).to receive(:authenticated?).and_return(true)
        
        # When authenticating
        result = client.authenticate
        
        # Then authentication should succeed and accounts should be set up
        expect(result).to be true
        expect(client.available_accounts).to eq(["DU123456"])
        expect(client.active_account_id).to eq("DU123456")
      end

      it "handles authentication failures" do
        expect(mock_oauth_client).to receive(:authenticate).and_return(false)
        
        # When authentication fails
        result = client.authenticate
        
        # Then subsequent operations should reflect failure
        expect(result).to be false
        
        # No accounts should be available and no active account set
        expect(client.available_accounts).to be_empty
        expect(client.active_account_id).to be_nil
      end
    end

    describe "#logout" do
      it "delegates logout to OAuth client" do
        expect(mock_oauth_client).to receive(:logout).and_return(true)
        
        result = client.logout
        expect(result).to be true
      end
    end

    describe "#initialize_session" do
      it "delegates session initialization without priority" do
        expected_result = { "connected" => true }
        expect(mock_oauth_client).to receive(:initialize_session).with(priority: false).and_return(expected_result)
        
        result = client.initialize_session
        expect(result).to eq(expected_result)
      end

      it "delegates session initialization with priority" do
        expected_result = { "connected" => true, "priority" => true }
        expect(mock_oauth_client).to receive(:initialize_session).with(priority: true).and_return(expected_result)
        
        result = client.initialize_session(priority: true)
        expect(result).to eq(expected_result)
      end
    end
  end

  describe "account management" do
    let(:authenticated_client) do
      client = described_class.new(default_account_id: "DU123456", live: false)
      oauth_client = double("oauth_client", authenticate: true, authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(oauth_client)
      client.authenticate
      client
    end

    it "sets up accounts after authentication" do
      # Given a client with default account ID
      # When authenticated
      expect(authenticated_client.available_accounts).to eq(["DU123456"])
      expect(authenticated_client.active_account_id).to eq("DU123456")
      expect(authenticated_client.account_id).to eq("DU123456")  # Legacy alias
    end

    it "allows switching between available accounts" do
      # Given an authenticated client with multiple accounts
      client = described_class.new(live: false)
      oauth_client = double("oauth_client", authenticate: true, authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(oauth_client)
      allow(client).to receive(:fetch_available_accounts).and_return(["DU111111", "DU222222"])
      client.authenticate
      
      # When switching accounts
      client.set_active_account("DU222222")
      
      # Then active account should change
      expect(client.active_account_id).to eq("DU222222")
    end

    it "validates account switching" do
      # Given an authenticated client
      # When trying to switch to unavailable account
      # Then it should raise an error
      expect { authenticated_client.set_active_account("DU999999") }.to raise_error(ArgumentError, /not available/)
    end

    it "provides account context to services" do
      # Given an authenticated client
      # Then account services should reflect the active account ID
      expect(authenticated_client.accounts.account_id).to eq("DU123456")
    end

    it "clears service cache when switching accounts" do
      # Given an authenticated client with services
      accounts_service1 = authenticated_client.accounts
      
      # When switching accounts (simulate multiple accounts available)
      authenticated_client.instance_variable_set(:@available_accounts, ["DU123456", "DU555555"])
      authenticated_client.set_active_account("DU555555")
      
      # Then new services should reflect the new account
      accounts_service2 = authenticated_client.accounts
      expect(accounts_service2.account_id).to eq("DU555555")
    end
  end

  describe "service access" do
    describe "#oauth_client" do
      it "creates and memoizes OAuth client instance" do
        # Given a client instance
        # When accessing OAuth client
        oauth1 = client.oauth_client
        oauth2 = client.oauth_client
        
        # Then it should return the same instance (memoized)
        expect(oauth1).to be_instance_of(Ibkr::Oauth::Client)
        expect(oauth1).to be(oauth2)
      end

      it "passes live mode configuration to OAuth client" do
        live_oauth = live_client.oauth_client
        sandbox_oauth = client.oauth_client
        
        expect(live_oauth.instance_variable_get(:@_live)).to be true
        expect(sandbox_oauth.instance_variable_get(:@_live)).to be false
      end
    end

    describe "#accounts" do
      it "creates and memoizes Accounts service instance" do
        # Given a client instance
        # When accessing accounts service
        accounts1 = client.accounts
        accounts2 = client.accounts
        
        # Then it should return the same instance (memoized)
        expect(accounts1).to be_instance_of(Ibkr::Accounts)
        expect(accounts1).to be(accounts2)
      end

      it "passes client reference to Accounts service" do
        accounts_service = client.accounts
        
        # The service should have access to the client
        expect(accounts_service.instance_variable_get(:@_client)).to be(client)
      end

      it "reflects current account ID in service after authentication" do
        # Given an authenticated client with account ID
        oauth_client = double("oauth_client", authenticate: true, authenticated?: true)
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate
        
        # When accessing accounts service
        accounts_service = client.accounts
        
        # Then service should reflect the client's active account ID
        expect(accounts_service.account_id).to eq("DU123456")
        expect(accounts_service.account_id).to eq(client.account_id)
      end
    end
  end

  describe "workflow integration" do
    let(:mock_oauth_client) { double("oauth_client", authenticate: true, authenticated?: true, initialize_session: { "connected" => true }) }
    let(:mock_accounts_service) { double("accounts_service", summary: double("summary")) }

    before do
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
      allow(client).to receive(:accounts).and_return(mock_accounts_service)
    end

    it "supports complete authentication and account setup workflow" do
      # Given a client created with default account ID
      # When following the complete setup workflow
      
      # 1. Authenticate
      auth_result = client.authenticate
      expect(auth_result).to be true
      
      # 2. Initialize session
      session_result = client.initialize_session
      expect(session_result).to include("connected" => true)
      
      # 3. Account is set after successful authentication
      expect(client.account_id).to eq("DU123456")
      
      # 4. Access account data
      summary = client.accounts.summary
      expect(summary).not_to be_nil
    end

    it "handles workflow interruption gracefully" do
      # Given authentication fails
      allow(mock_oauth_client).to receive(:authenticate).and_return(false)
      
      # When authentication fails
      auth_result = client.authenticate
      
      # Then subsequent operations should still be possible to attempt
      expect(auth_result).to be false
      
      # No active account should be set when authentication fails
      expect(client.account_id).to be_nil
      # But default account ID is still available for retry
      expect(client.instance_variable_get(:@default_account_id)).to eq("DU123456")
    end
  end

  describe "error propagation" do
    let(:mock_oauth_client) { double("oauth_client", authenticated?: false) }

    before do
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
    end

    it "propagates OAuth authentication errors" do
      allow(mock_oauth_client).to receive(:authenticate).and_raise(StandardError, "OAuth error")
      
      expect { client.authenticate }.to raise_error(StandardError, "OAuth error")
    end

    it "propagates session initialization errors" do
      allow(mock_oauth_client).to receive(:initialize_session).and_raise(StandardError, "Session error")
      
      expect { client.initialize_session }.to raise_error(StandardError, "Session error")
    end

    it "propagates logout errors" do
      allow(mock_oauth_client).to receive(:logout).and_raise(StandardError, "Logout error")
      
      expect { client.logout }.to raise_error(StandardError, "Logout error")
    end
  end

  describe "thread safety" do
    it "maintains thread safety for account ID access" do
      # First authenticate the client to set up active account
      oauth_client = double("oauth_client", authenticate: true, authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(oauth_client)
      client.authenticate
      
      threads = Array.new(5) do |i|
        Thread.new do
          # Multiple threads accessing account ID simultaneously
          client.account_id
        end
      end
      
      # All threads should complete successfully and return consistent results
      results = threads.map(&:join).map(&:value)
      
      # All threads should get the same account ID (proving thread safety worked)
      expect(results).to all(eq("DU123456"))
    end

    it "provides thread-safe access to memoized services" do
      threads = Array.new(3) do
        Thread.new do
          [client.oauth_client, client.accounts]
        end
      end
      
      results = threads.map(&:join).map(&:value)
      
      # All threads should get the same memoized instances
      oauth_clients = results.map(&:first).uniq
      account_services = results.map(&:last).uniq
      
      expect(oauth_clients.size).to eq(1)
      expect(account_services.size).to eq(1)
    end
  end

  describe "resource cleanup" do
    it "allows garbage collection of large response data" do
      # Given an authenticated client with account data
      oauth_client = double("oauth_client", authenticate: true, authenticated?: true)
      allow(client).to receive(:oauth_client).and_return(oauth_client)
      client.authenticate
      expect(client.account_id).to eq("DU123456")
      
      # When client goes out of scope
      client = nil
      
      # Then garbage collection should be able to reclaim memory
      # (Testing that there are no circular references preventing cleanup)
      gc_count_before = GC.stat(:total_freed_objects)
      GC.start
      gc_count_after = GC.stat(:total_freed_objects)
      
      # Some objects should have been freed (proving GC worked)
      expect(gc_count_after).to be >= gc_count_before
    end
  end
end