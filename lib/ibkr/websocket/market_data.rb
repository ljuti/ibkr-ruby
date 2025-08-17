# frozen_string_literal: true

module Ibkr
  module WebSocket
    # Market data interface wrapper for WebSocket client
    # Provides a focused interface for market data operations
    class MarketData
      attr_reader :websocket_client

      def initialize(websocket_client)
        @websocket_client = websocket_client
      end

      # Delegate all methods to the WebSocket client
      def method_missing(method, *args, &block)
        @websocket_client.send(method, *args, &block)
      end

      def respond_to_missing?(method, include_private = false)
        @websocket_client.respond_to?(method, include_private) || super
      end
    end
  end
end