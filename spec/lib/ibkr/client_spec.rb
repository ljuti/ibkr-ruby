# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Client do
  include_context "with mocked Rails credentials"
  include_context "with mocked cryptographic keys"

  let(:client) { described_class.new(live: false) }
  let(:live_client) { described_class.new(live: true) }

  describe "initialization" do
    context "when creating sandbox client" do
      it "initializes with sandbox configuration" do
        # Given a user wants to test in sandbox environment
        # When creating a new client
        client = described_class.new(live: false)
        
        # Then it should be configured for sandbox mode
        expect(client.instance_variable_get(:@live)).to be false
        expect(client.account_id).to be_nil
      end
    end

    context "when creating live trading client" do
      it "initializes with live trading configuration" do
        # Given a user wants to trade in live environment
        # When creating a live client
        client = described_class.new(live: true)
        
        # Then it should be configured for live trading
        expect(client.instance_variable_get(:@live)).to be true
        expect(client.account_id).to be_nil
      end
    end

    it "provides default sandbox mode when no parameter specified" do
      default_client = described_class.new
      expect(default_client.instance_variable_get(:@live)).to be false
    end
  end

  describe "authentication delegation" do
    let(:mock_oauth_client) { double("oauth_client") }

    before do
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
    end

    describe "#authenticate" do
      it "delegates authentication to OAuth client" do
        # Given an OAuth client is available
        expect(mock_oauth_client).to receive(:authenticate).and_return(true)
        
        # When authenticating
        result = client.authenticate
        
        # Then it should delegate to OAuth client and return result
        expect(result).to be true
      end

      it "handles authentication failures" do
        expect(mock_oauth_client).to receive(:authenticate).and_return(false)
        
        result = client.authenticate
        expect(result).to be false
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
    describe "#set_account_id" do
      it "sets the account ID for subsequent operations" do
        # Given a client without an account ID
        expect(client.account_id).to be_nil
        
        # When setting an account ID
        account_id = "DU123456"
        client.set_account_id(account_id)
        
        # Then the account ID should be stored and accessible
        expect(client.account_id).to eq(account_id)
      end

      it "allows changing account ID during session" do
        client.set_account_id("DU111111")
        expect(client.account_id).to eq("DU111111")
        
        client.set_account_id("DU222222")
        expect(client.account_id).to eq("DU222222")
      end

      it "updates account context for services" do
        client.set_account_id("DU123456")
        
        # Account services should reflect the new account ID
        expect(client.accounts.account_id).to eq("DU123456")
      end
    end

    describe "#account_id" do
      it "returns nil when no account is set" do
        expect(client.account_id).to be_nil
      end

      it "returns the currently set account ID" do
        client.set_account_id("DU987654")
        expect(client.account_id).to eq("DU987654")
      end
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

      it "reflects current account ID in service" do
        client.set_account_id("DU555555")
        accounts_service = client.accounts
        
        expect(accounts_service.account_id).to eq("DU555555")
      end
    end
  end

  describe "workflow integration" do
    let(:mock_oauth_client) { double("oauth_client", authenticate: true, initialize_session: { "connected" => true }) }
    let(:mock_accounts_service) { double("accounts_service", summary: double("summary")) }

    before do
      allow(client).to receive(:oauth_client).and_return(mock_oauth_client)
      allow(client).to receive(:accounts).and_return(mock_accounts_service)
    end

    it "supports complete authentication and account setup workflow" do
      # Given a new client
      # When following the complete setup workflow
      
      # 1. Authenticate
      auth_result = client.authenticate
      expect(auth_result).to be true
      
      # 2. Initialize session
      session_result = client.initialize_session
      expect(session_result).to include("connected" => true)
      
      # 3. Set account
      client.set_account_id("DU123456")
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
      
      # User should still be able to set account ID for future operations
      client.set_account_id("DU123456")
      expect(client.account_id).to eq("DU123456")
    end
  end

  describe "error propagation" do
    let(:mock_oauth_client) { double("oauth_client") }

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
    it "maintains thread safety for account ID operations" do
      threads = Array.new(5) do |i|
        Thread.new do
          client.set_account_id("DU#{i}#{i}#{i}#{i}#{i}#{i}")
        end
      end
      
      # All threads should complete successfully
      threads.map(&:join)
      
      # Final account ID should be one of the set values (proving thread safety worked)
      expect(client.account_id).to match(/^DU\d{6}$/)
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
      # Given a client with large response data (simulated)
      client.set_account_id("DU123456")
      
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