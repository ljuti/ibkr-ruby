# frozen_string_literal: true

module Ibkr
  module WebSocket
    # Configuration object for WebSocket settings and constants
    # Centralizes all magic numbers, timeouts, and default values
    class Configuration
      attr_accessor :reconnect_attempts, :heartbeat_interval, :connection_timeout

      # Connection timeouts
      CONNECTION_TIMEOUT = 10 # seconds
      HEARTBEAT_INTERVAL = 30 # seconds
      HEARTBEAT_STALE_THRESHOLD = 2 # multiplier for heartbeat interval

      # EventMachine settings
      EM_START_WAIT_INTERVAL = 0.1 # seconds to wait for EM to start
      EM_INITIALIZATION_DELAY = 0.1 # seconds for EM to fully initialize
      CONNECTION_ESTABLISHMENT_WAIT = 0.01 # seconds between connection checks

      # Subscription limits
      DEFAULT_SUBSCRIPTION_LIMITS = {
        total: 100,
        market_data: 50,
        portfolio: 5,
        orders: 10
      }.freeze

      # Rate limiting
      DEFAULT_RATE_LIMIT = 60 # requests per minute
      RATE_LIMIT_HISTORY_DURATION = 3600 # seconds (1 hour)

      # Message processing
      MAX_MESSAGE_ERRORS = 100
      MAX_PROCESSING_TIMES = 1000
      PROCESSING_TIMES_CLEANUP_BATCH = 100

      # Circuit breaker
      CIRCUIT_BREAKER_FAILURE_THRESHOLD = 5
      CIRCUIT_BREAKER_TIMEOUT = 300 # seconds

      # WebSocket endpoints
      WEBSOCKET_ENDPOINTS = {
        production: "wss://api.ibkr.com/v1/api/ws",
        live: "wss://api.ibkr.com/v1/api/ws",
        paper: "wss://api.ibkr.com/v1/api/ws"
      }.freeze

      # Connection headers
      DEFAULT_HEADERS = {
        "Connection" => "Upgrade",
        "Upgrade" => "websocket",
        "Origin" => "interactivebrokers.github.io"
      }.freeze

      # IBKR message formats
      IBKR_PING_MESSAGE = "tic"
      ACCOUNT_SUMMARY_SUBSCRIBE_FORMAT = "ssd+%s+%s" # accountId + params
      ACCOUNT_SUMMARY_UNSUBSCRIBE_FORMAT = "usd+%s" # accountId

      # Default subscription parameters
      DEFAULT_ACCOUNT_SUMMARY_KEYS = [
        "AccruedCash-S",
        "ExcessLiquidity-S",
        "NetLiquidation-S"
      ].freeze

      DEFAULT_ACCOUNT_SUMMARY_FIELDS = [
        "currency",
        "monetaryValue"
      ].freeze

      def initialize
        @reconnect_attempts = 3
        @heartbeat_interval = HEARTBEAT_INTERVAL
        @connection_timeout = CONNECTION_TIMEOUT
      end

      class << self
        # Get WebSocket endpoint for environment
        #
        # @param environment [String] Environment name
        # @return [String] WebSocket endpoint URL
        def websocket_endpoint(environment)
          WEBSOCKET_ENDPOINTS[environment.to_sym] || WEBSOCKET_ENDPOINTS[:production]
        end

        # Get default headers with version info
        #
        # @param version [String] Gem version
        # @return [Hash] Headers hash
        def default_headers(version)
          DEFAULT_HEADERS.merge(
            "User-Agent" => "IBKR-Ruby-#{version}",
            "X-IBKR-Client-Version" => version
          )
        end

        # Check if heartbeat is stale
        #
        # @param last_pong [Time] Last pong received time
        # @return [Boolean] True if heartbeat is stale
        def heartbeat_stale?(last_pong)
          return true unless last_pong
          Time.now - last_pong > (HEARTBEAT_INTERVAL * HEARTBEAT_STALE_THRESHOLD)
        end
      end
    end
  end
end
