# frozen_string_literal: true

module Ibkr
  module WebSocket
    # Streaming interface wrapper for WebSocket client
    # Provides a focused interface for streaming operations
    class Streaming
      attr_reader :client

      def initialize(websocket_client)
        @client = websocket_client
      end

      # Delegate all methods to the WebSocket client
      def method_missing(method, *args, &block)
        @client.send(method, *args, &block)
      end

      def respond_to_missing?(method, include_private = false)
        @client.respond_to?(method, include_private) || super
      end
    end
  end
end