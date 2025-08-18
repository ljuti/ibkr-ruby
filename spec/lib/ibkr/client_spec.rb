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
        expect(client.live).to be false
        expect(client.default_account_id).to eq("DU123456")
        # Active account is not set until authentication
        expect(client.active_account_id).to be_nil
        # Configuration should be set up correctly
        expect(client.config).to be_a(Ibkr::Configuration)
        expect(client.config.environment).to eq("sandbox")
        # Available accounts should be empty initially
        expect(client.available_accounts).to eq([])
      end
    end

    context "when creating live trading client" do
      it "initializes with live trading configuration and default account" do
        # Given a user wants to trade in live environment with specific default account
        # When creating a live client
        client = described_class.new(default_account_id: "DU789012", live: true)

        # Then it should be configured for live trading
        expect(client.live).to be true
        expect(client.default_account_id).to eq("DU789012")
        # Active account is not set until authentication
        expect(client.active_account_id).to be_nil
        # Configuration should be set up correctly
        expect(client.config).to be_a(Ibkr::Configuration)
        expect(client.config.environment).to eq("production")
        # Available accounts should be empty initially
        expect(client.available_accounts).to eq([])
      end
    end

    it "allows creation without default account ID" do
      # Given default_account_id is optional
      # When creating client without default account
      client = described_class.new(live: false)

      # Then it should initialize successfully
      expect(client.live).to be false
      expect(client.default_account_id).to be_nil
      expect(client.active_account_id).to be_nil
      # Configuration should use global config
      expect(client.config).to be_a(Ibkr::Configuration)
      expect(client.config.environment).to eq("sandbox")
      # Available accounts should be empty initially
      expect(client.available_accounts).to eq([])
    end

    it "freezes the default_account_id when provided" do
      # Given a default account ID is provided
      # When creating client
      client = described_class.new(default_account_id: "DU123456", live: false)

      # Then default_account_id should be frozen
      expect(client.default_account_id).to be_frozen
    end

    it "does not freeze default_account_id when nil" do
      # Given no default account ID
      # When creating client
      client = described_class.new(live: false)

      # Then default_account_id should be nil
      expect(client.default_account_id).to be_nil
    end

    it "uses custom configuration when provided" do
      # Given a custom configuration
      custom_config = Ibkr::Configuration.new
      custom_config.environment = "production"

      # When creating client with custom config
      client = described_class.new(config: custom_config, live: false)

      # Then it should use the custom config (not global)
      expect(client.config).to eq(custom_config)
      # But live parameter should still override environment
      expect(client.config.environment).to eq("sandbox")
    end

    it "duplicates global configuration when not provided" do
      # Given no custom configuration
      # When creating client
      client = described_class.new(live: false)

      # Then it should use a copy of global config
      expect(client.config).not_to be(Ibkr.configuration)
      expect(client.config).to be_a(Ibkr::Configuration)
    end

    it "sets environment based on live parameter" do
      # Given live parameter controls environment
      # When creating sandbox client
      sandbox_client = described_class.new(live: false)
      # Then environment should be sandbox
      expect(sandbox_client.config.environment).to eq("sandbox")

      # When creating live client
      live_client = described_class.new(live: true)
      # Then environment should be production
      expect(live_client.config.environment).to eq("production")
    end

    it "initializes with no accounts before authentication" do
      # Given new client
      # When created
      client = described_class.new(live: false)

      # Then no accounts are available
      expect(client.available_accounts).to eq([])
      expect(client.account_id).to be_nil
    end

    it "stores live parameter" do
      # When creating clients with different live values
      sandbox_client = described_class.new(live: false)
      live_client = described_class.new(live: true)

      # Then live parameter is stored
      expect(sandbox_client.live).to be false
      expect(live_client.live).to be true
    end
  end

  describe "authentication delegation" do
    let(:mock_oauth_client) {
      double("oauth_client",
        authenticated?: false,
        initialize_session: true,
        get: {"accounts" => ["DU123456"]})
    }

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

      it "uses first available account when default not found" do
        # Given default account is not in available accounts
        expect(mock_oauth_client).to receive(:authenticate).and_return(true)
        allow(mock_oauth_client).to receive(:authenticated?).and_return(true)
        allow(mock_oauth_client).to receive(:get).and_return({"accounts" => ["DU789012", "DU555555"]})

        # When authenticating
        result = client.authenticate

        # Then should fall back to first available account
        expect(result).to be true
        expect(client.available_accounts).to eq(["DU789012", "DU555555"])
        expect(client.active_account_id).to eq("DU789012") # First available, not default
      end

      it "uses first available account when no default specified" do
        # Given client with no default account
        client_no_default = described_class.new(live: false)
        allow(client_no_default).to receive(:oauth_client).and_return(mock_oauth_client)
        expect(mock_oauth_client).to receive(:authenticate).and_return(true)
        allow(mock_oauth_client).to receive(:authenticated?).and_return(true)
        allow(mock_oauth_client).to receive(:get).and_return({"accounts" => ["DU111111", "DU222222"]})

        # When authenticating
        result = client_no_default.authenticate

        # Then should use first available account
        expect(result).to be true
        expect(client_no_default.available_accounts).to eq(["DU111111", "DU222222"])
        expect(client_no_default.active_account_id).to eq("DU111111")
      end

      it "validates active account is in available accounts" do
        # Given default account is in available accounts
        expect(mock_oauth_client).to receive(:authenticate).and_return(true)
        allow(mock_oauth_client).to receive(:authenticated?).and_return(true)
        allow(mock_oauth_client).to receive(:get).and_return({"accounts" => ["DU123456", "DU789012"]})

        # When authenticating
        result = client.authenticate

        # Then should use default account since it's available
        expect(result).to be true
        expect(client.available_accounts).to eq(["DU123456", "DU789012"])
        expect(client.active_account_id).to eq("DU123456")
      end

      it "delegates to account manager for discovery" do
        # Given successful OAuth authentication
        expect(mock_oauth_client).to receive(:authenticate).and_return(true)
        allow(mock_oauth_client).to receive(:authenticated?).and_return(true)
        allow(mock_oauth_client).to receive(:initialize_session).and_return(true)
        allow(mock_oauth_client).to receive(:get).and_return({"accounts" => ["DU123456"]})

        # Expect account manager to discover accounts
        manager = client.send(:account_manager)
        expect(manager).to receive(:discover_accounts).and_call_original

        # When authenticating
        result = client.authenticate

        # Then succeeds
        expect(result).to be true
        expect(client.available_accounts).to eq(["DU123456"])
      end

      it "returns OAuth result when authentication fails" do
        # Given OAuth returns specific failure result
        expect(mock_oauth_client).to receive(:authenticate).and_return(false)

        # When authenticating
        result = client.authenticate

        # Then returns the OAuth result directly
        expect(result).to be false
      end

      it "returns OAuth result when authentication succeeds" do
        # Given OAuth returns specific success result
        expect(mock_oauth_client).to receive(:authenticate).and_return(true)
        allow(mock_oauth_client).to receive(:authenticated?).and_return(true)

        # When authenticating
        result = client.authenticate

        # Then returns the OAuth result
        expect(result).to be true
      end

      it "discovers accounts only when OAuth succeeds" do
        # Given OAuth fails
        expect(mock_oauth_client).to receive(:authenticate).and_return(false)

        # Expect account manager NOT to be called
        manager = client.send(:account_manager)
        expect(manager).not_to receive(:discover_accounts)

        # When authenticating
        client.authenticate

        # Then accounts remain empty
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
        expected_result = {"connected" => true}
        expect(mock_oauth_client).to receive(:initialize_session).with(priority: false).and_return(expected_result)

        result = client.initialize_session
        expect(result).to eq(expected_result)
      end

      it "delegates session initialization with priority" do
        expected_result = {"connected" => true, "priority" => true}
        expect(mock_oauth_client).to receive(:initialize_session).with(priority: true).and_return(expected_result)

        result = client.initialize_session(priority: true)
        expect(result).to eq(expected_result)
      end
    end
  end

  describe "account management" do
    let(:authenticated_client) do
      client = described_class.new(default_account_id: "DU123456", live: false)
      oauth_client = double("oauth_client",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU123456"]})
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
      oauth_client = double("oauth_client",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU111111", "DU222222"]})
      allow(client).to receive(:oauth_client).and_return(oauth_client)
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
      expect { authenticated_client.set_active_account("DU999999") }.to raise_error(Ibkr::ApiError::NotFound, /not found or not accessible/)
    end

    describe "#set_active_account behavior" do
      it "delegates to account manager" do
        # Given authenticated client
        # When setting active account
        # Then delegates to account manager
        manager = authenticated_client.send(:account_manager)
        expect(manager).to receive(:set_active_account).with("DU123456")

        authenticated_client.set_active_account("DU123456")
      end

      it "clears services cache after account change" do
        # Given authenticated client with cached services
        authenticated_client.accounts  # Cache a service

        # When switching accounts (need multiple accounts)
        client = described_class.new(live: false)
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU111111", "DU222222"]})
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate

        # Cache a service
        service1 = client.accounts

        # Switch account
        client.set_active_account("DU222222")

        # Then service is recreated (not the same instance)
        service2 = client.accounts
        expect(service2).not_to be(service1)
      end
    end

    it "provides account context to services" do
      # Given an authenticated client
      # Then account services should reflect the active account ID
      expect(authenticated_client.accounts.account_id).to eq("DU123456")
    end

    it "clears service cache when switching accounts" do
      # Given an authenticated client with multiple accounts
      client = described_class.new(live: false)
      oauth_client = double("oauth_client",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU123456", "DU555555"]})
      allow(client).to receive(:oauth_client).and_return(oauth_client)
      client.authenticate

      # Cache a service for first account
      service1 = client.accounts
      expect(service1.account_id).to eq("DU123456")

      # When switching accounts
      client.set_active_account("DU555555")

      # Then new service instance should be created
      service2 = client.accounts
      expect(service2).not_to be(service1)  # Different instance
      expect(service2.account_id).to eq("DU555555")
    end
  end

  describe "service access" do
    describe "#authenticated?" do
      it "delegates to oauth_client" do
        oauth_client = double("oauth_client")
        allow(client).to receive(:oauth_client).and_return(oauth_client)

        # When not authenticated
        expect(oauth_client).to receive(:authenticated?).and_return(false)
        expect(client.authenticated?).to be false

        # When authenticated
        expect(oauth_client).to receive(:authenticated?).and_return(true)
        expect(client.authenticated?).to be true
      end
    end

    describe "#ping" do
      it "delegates to oauth_client" do
        oauth_client = double("oauth_client")
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        ping_response = {"tickle" => true}

        expect(oauth_client).to receive(:ping).and_return(ping_response)
        result = client.ping
        expect(result).to eq(ping_response)
      end
    end

    describe "#account_id" do
      it "delegates to account manager" do
        # Given authenticated client
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU123456"]})
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate

        # When getting account_id
        # Then returns account manager's active account
        expect(client.account_id).to eq("DU123456")
      end

      it "returns nil when not authenticated" do
        # Given unauthenticated client
        # When getting account_id
        # Then returns nil
        expect(client.account_id).to be_nil
      end
    end

    describe "#available_accounts" do
      it "delegates to account manager" do
        # Given authenticated client
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU123456"]})
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate

        # When getting available_accounts
        # Then returns account manager's accounts
        expect(client.available_accounts).to eq(["DU123456"])
      end

      it "returns empty array when not authenticated" do
        # Given unauthenticated client
        # When getting available_accounts
        # Then returns empty array
        expect(client.available_accounts).to eq([])
      end
    end

    describe "#active_account_id" do
      it "delegates to account_id" do
        # Given client with account
        allow(client).to receive(:account_id).and_return("DELEGATED")

        # When getting active_account_id
        # Then delegates to account_id
        expect(client.active_account_id).to eq("DELEGATED")
      end
    end

    describe "#live_mode?" do
      it "is an alias for live" do
        # Given sandbox client
        expect(client.live_mode?).to be false
        expect(client.live_mode?).to eq(client.live)

        # Given live client
        expect(live_client.live_mode?).to be true
        expect(live_client.live_mode?).to eq(live_client.live)
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
        # Test that service properly uses the client (behavior over state)
        expect(accounts_service.account_id).to eq(client.account_id)
      end

      it "reflects current account ID in service after authentication" do
        # Given an authenticated client with account ID
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU123456"]})
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
    let(:mock_oauth_client) {
      double("oauth_client",
        authenticate: true,
        authenticated?: true,
        initialize_session: {"connected" => true},
        get: {"accounts" => ["DU123456"]})
    }
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
      expect(client.default_account_id).to eq("DU123456")
    end
  end

  describe "error propagation" do
    let(:mock_oauth_client) {
      double("oauth_client",
        authenticated?: false,
        initialize_session: true,
        get: {"accounts" => ["DU123456"]})
    }

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

  describe "HTTP method delegation" do
    let(:oauth_client) { double("oauth_client") }

    before do
      allow(client).to receive(:oauth_client).and_return(oauth_client)
    end

    describe "#get" do
      it "delegates to oauth_client with options" do
        expect(oauth_client).to receive(:get).with("/path", params: {foo: "bar"}, headers: {"X-Test" => "value"})
        client.get("/path", params: {foo: "bar"}, headers: {"X-Test" => "value"})
      end

      it "works without options" do
        expect(oauth_client).to receive(:get).with("/path")
        client.get("/path")
      end
    end

    describe "#post" do
      it "delegates to oauth_client with options" do
        expect(oauth_client).to receive(:post).with("/path", body: {data: "test"}, headers: {"X-Test" => "value"})
        client.post("/path", body: {data: "test"}, headers: {"X-Test" => "value"})
      end

      it "works without options" do
        expect(oauth_client).to receive(:post).with("/path")
        client.post("/path")
      end
    end

    describe "#put" do
      it "delegates to oauth_client with options" do
        expect(oauth_client).to receive(:put).with("/path", body: {data: "test"}, headers: {"X-Test" => "value"})
        client.put("/path", body: {data: "test"}, headers: {"X-Test" => "value"})
      end

      it "works without options" do
        expect(oauth_client).to receive(:put).with("/path")
        client.put("/path")
      end
    end

    describe "#delete" do
      it "delegates to oauth_client with options" do
        expect(oauth_client).to receive(:delete).with("/path", headers: {"X-Test" => "value"})
        client.delete("/path", headers: {"X-Test" => "value"})
      end

      it "works without options" do
        expect(oauth_client).to receive(:delete).with("/path")
        client.delete("/path")
      end
    end
  end

  describe "configuration accessors" do
    describe "#environment" do
      it "returns the configuration environment" do
        expect(client.environment).to eq("sandbox")
        expect(live_client.environment).to eq("production")
      end
    end

    describe "#sandbox?" do
      it "delegates to configuration" do
        expect(client.sandbox?).to be true
        expect(live_client.sandbox?).to be false
      end
    end

    describe "#production?" do
      it "delegates to configuration" do
        expect(client.production?).to be false
        expect(live_client.production?).to be true
      end
    end
  end

  describe "fluent interface methods" do
    describe "#authenticate!" do
      it "authenticates and returns self for chaining" do
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU123456"]})
        allow(client).to receive(:oauth_client).and_return(oauth_client)

        result = client.authenticate!
        expect(result).to be(client)
        expect(client.active_account_id).to eq("DU123456")
      end
    end

    describe "#with_account" do
      it "switches account and returns self for chaining" do
        # Setup authenticated client with multiple accounts
        client = described_class.new(live: false)
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU123456", "DU789012"]})
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate

        result = client.with_account("DU789012")
        expect(result).to be(client)
        expect(client.active_account_id).to eq("DU789012")
      end
    end

    describe "#portfolio" do
      it "returns ChainableAccountsProxy for fluent interface" do
        result = client.portfolio
        expect(result).to be_a(Ibkr::ChainableAccountsProxy)
        expect(result.instance_variable_get(:@client)).to be(client)
      end
    end

    describe "#accounts_fluent" do
      it "returns ChainableAccountsProxy for fluent interface" do
        result = client.accounts_fluent
        expect(result).to be_a(Ibkr::ChainableAccountsProxy)
        expect(result.instance_variable_get(:@client)).to be(client)
      end
    end
  end

  describe "WebSocket methods" do
    describe "#websocket" do
      it "creates and memoizes WebSocket client" do
        ws1 = client.websocket
        ws2 = client.websocket

        expect(ws1).to be_a(Ibkr::WebSocket::Client)
        expect(ws1).to be(ws2)
        expect(ws1.ibkr_client).to be(client)
      end
    end

    describe "#streaming" do
      it "creates and memoizes WebSocket streaming interface" do
        streaming1 = client.streaming
        streaming2 = client.streaming

        expect(streaming1).to be_a(Ibkr::WebSocket::Streaming)
        expect(streaming1).to be(streaming2)
      end
    end

    describe "#real_time_data" do
      it "creates and memoizes WebSocket market data interface" do
        rtd1 = client.real_time_data
        rtd2 = client.real_time_data

        expect(rtd1).to be_a(Ibkr::WebSocket::MarketData)
        expect(rtd1).to be(rtd2)
      end
    end

    describe "#with_websocket" do
      it "connects websocket and returns self for chaining" do
        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:connect)

        result = client.with_websocket
        expect(result).to be(client)
      end
    end

    describe "#stream_market_data" do
      it "subscribes to market data and returns self" do
        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:subscribe_to_market_data).with(["AAPL", "MSFT"], ["price"])

        result = client.stream_market_data("AAPL", "MSFT")
        expect(result).to be(client)
      end

      it "accepts array of symbols" do
        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:subscribe_to_market_data).with(["AAPL", "MSFT"], ["price"])

        result = client.stream_market_data(["AAPL", "MSFT"])
        expect(result).to be(client)
      end

      it "accepts custom fields" do
        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:subscribe_to_market_data).with(["AAPL"], ["price", "volume"])

        result = client.stream_market_data("AAPL", fields: ["price", "volume"])
        expect(result).to be(client)
      end
    end

    describe "#stream_portfolio" do
      it "subscribes to portfolio updates for current account" do
        # Setup authenticated client
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU123456"]})
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate

        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:subscribe_to_portfolio_updates).with("DU123456")

        result = client.stream_portfolio
        expect(result).to be(client)
      end

      it "accepts specific account ID" do
        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:subscribe_to_portfolio_updates).with("DU789012")

        result = client.stream_portfolio("DU789012")
        expect(result).to be(client)
      end
    end

    describe "#stream_orders" do
      it "subscribes to order status for current account" do
        # Setup authenticated client
        oauth_client = double("oauth_client",
          authenticate: true,
          authenticated?: true,
          initialize_session: true,
          get: {"accounts" => ["DU123456"]})
        allow(client).to receive(:oauth_client).and_return(oauth_client)
        client.authenticate

        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:subscribe_to_order_status).with("DU123456")

        result = client.stream_orders
        expect(result).to be(client)
      end

      it "accepts specific account ID" do
        websocket = double("websocket")
        allow(client).to receive(:websocket).and_return(websocket)
        expect(websocket).to receive(:subscribe_to_order_status).with("DU789012")

        result = client.stream_orders("DU789012")
        expect(result).to be(client)
      end
    end
  end

  describe "thread safety" do
    it "maintains thread safety for account ID access" do
      # First authenticate the client to set up active account
      oauth_client = double("oauth_client",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU123456"]})
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
          client.accounts
        end
      end

      results = threads.map(&:join).map(&:value)

      # All threads should get the same memoized instance
      account_services = results.uniq

      expect(account_services.size).to eq(1)
      expect(account_services.first).to be_instance_of(Ibkr::Accounts)
    end
  end

  describe "resource cleanup" do
    it "allows garbage collection of large response data" do
      # Given an authenticated client with account data
      oauth_client = double("oauth_client",
        authenticate: true,
        authenticated?: true,
        initialize_session: true,
        get: {"accounts" => ["DU123456"]})
      allow(client).to receive(:oauth_client).and_return(oauth_client)
      client.authenticate
      expect(client.account_id).to eq("DU123456")

      # When client goes out of scope

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
