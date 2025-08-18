# frozen_string_literal: true

module Ibkr
  # Facade for WebSocket operations providing a simplified interface.
  #
  # This class encapsulates WebSocket functionality and provides both
  # individual service access and fluent interface methods for real-time
  # market data, portfolio updates, and order status streaming.
  #
  # @example Basic usage
  #   facade = WebSocketFacade.new(client)
  #   facade.connect
  #   facade.subscribe_market_data(["AAPL"])
  #
  # @example Fluent interface
  #   facade.with_connection.stream_market_data("AAPL").stream_portfolio
  #
  class WebSocketFacade
    attr_reader :client

    # Initialize WebSocket facade.
    #
    # @param client [Ibkr::Client] The main client instance
    def initialize(client)
      @client = client
    end

    # Get WebSocket client (lazy-loaded).
    #
    # @return [Ibkr::WebSocket::Client] WebSocket client instance
    def websocket
      @websocket_client ||= WebSocket::Client.new(client)
    end

    # Get streaming interface (lazy-loaded).
    #
    # @return [Ibkr::WebSocket::Streaming] Streaming interface
    def streaming
      @streaming ||= WebSocket::Streaming.new(websocket)
    end

    # Get real-time market data interface (lazy-loaded).
    #
    # @return [Ibkr::WebSocket::MarketData] Market data interface
    def real_time_data
      @real_time_data ||= WebSocket::MarketData.new(websocket)
    end

    # Connect to WebSocket server.
    #
    # @return [self] Returns self for method chaining
    def connect
      websocket.connect
      self
    end

    # Alias for connect to provide fluent interface naming.
    #
    # @return [self] Returns self for method chaining
    def with_connection
      connect
    end

    # Subscribe to market data for specified symbols.
    #
    # @param symbols [Array<String>, String] Symbols to subscribe to
    # @param fields [Array<String>] Data fields to receive
    # @return [self] Returns self for method chaining
    def subscribe_market_data(symbols, fields: ["price"])
      websocket.subscribe_to_market_data(Array(symbols), fields)
      self
    end

    # Subscribe to portfolio updates.
    #
    # @param account_id [String, nil] Account ID (uses client's active account if nil)
    # @return [self] Returns self for method chaining
    def subscribe_portfolio(account_id = nil)
      target_account = account_id || client.active_account_id
      websocket.subscribe_to_portfolio_updates(target_account)
      self
    end

    # Subscribe to order status updates.
    #
    # @param account_id [String, nil] Account ID (uses client's active account if nil)
    # @return [self] Returns self for method chaining
    def subscribe_orders(account_id = nil)
      target_account = account_id || client.active_account_id
      websocket.subscribe_to_order_status(target_account)
      self
    end

    # Fluent interface alias for subscribe_market_data.
    #
    # @param symbols [Array<String>, String] Symbols to subscribe to
    # @param fields [Array<String>] Data fields to receive
    # @return [self] Returns self for method chaining
    def stream_market_data(*symbols, fields: ["price"])
      subscribe_market_data(symbols.flatten, fields: fields)
    end

    # Fluent interface alias for subscribe_portfolio.
    #
    # @param account_id [String, nil] Account ID (uses client's active account if nil)
    # @return [self] Returns self for method chaining
    def stream_portfolio(account_id = nil)
      subscribe_portfolio(account_id)
    end

    # Fluent interface alias for subscribe_orders.
    #
    # @param account_id [String, nil] Account ID (uses client's active account if nil)
    # @return [self] Returns self for method chaining
    def stream_orders(account_id = nil)
      subscribe_orders(account_id)
    end
  end
end