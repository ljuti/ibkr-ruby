# frozen_string_literal: true

module Ibkr
  module WebSocket
    module ValueObjects
      # Value object representing a WebSocket subscription request
      #
      # Encapsulates all parameters needed for creating a subscription,
      # reducing parameter coupling and making the API cleaner.
      #
      # @example Market data subscription
      #   request = SubscriptionRequest.new(
      #     channel: "market_data",
      #     symbols: ["AAPL", "MSFT"],
      #     fields: ["price", "volume"]
      #   )
      #
      # @example Portfolio subscription
      #   request = SubscriptionRequest.new(
      #     channel: "portfolio",
      #     account_id: "DU123456"
      #   )
      #
      class SubscriptionRequest
        attr_reader :channel, :symbols, :fields, :account_id, :keys, :params

        # @param channel [String] Subscription channel type
        # @param symbols [Array<String>] Stock symbols (for market data)
        # @param fields [Array<String>] Data fields to subscribe to
        # @param account_id [String] Account ID (for portfolio/orders)
        # @param keys [Array<String>] Specific keys (for account summary)
        # @param params [Hash] Additional parameters
        def initialize(channel:, symbols: nil, fields: nil, account_id: nil, keys: nil, **params)
          @channel = channel.to_s.freeze
          @symbols = symbols&.map(&:to_s)&.freeze
          @fields = fields&.map(&:to_s)&.freeze
          @account_id = account_id&.to_s&.freeze
          @keys = keys&.map(&:to_s)&.freeze
          @params = params.freeze

          validate!
        end

        # Convert to hash for sending over WebSocket
        #
        # @return [Hash] Subscription parameters
        def to_h
          {
            channel: @channel,
            symbols: @symbols,
            fields: @fields,
            account_id: @account_id,
            keys: @keys
          }.merge(@params).compact
        end

        # Check if this is a market data subscription
        #
        # @return [Boolean]
        def market_data?
          @channel == "market_data"
        end

        # Check if this is a portfolio subscription
        #
        # @return [Boolean]
        def portfolio?
          @channel == "portfolio"
        end

        # Check if this is an orders subscription
        #
        # @return [Boolean]
        def orders?
          @channel == "orders"
        end

        # Check if this is an account summary subscription
        #
        # @return [Boolean]
        def account_summary?
          @channel == "account_summary"
        end

        # Generate a unique identifier for this subscription
        #
        # @return [String] Unique subscription identifier
        def subscription_id
          parts = [@channel]
          parts << @symbols.join(",") if @symbols
          parts << @account_id if @account_id
          parts << @fields.join(",") if @fields
          parts.join(":")
        end

        # Check equality with another subscription request
        #
        # @param other [Object] Object to compare with
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(SubscriptionRequest)

          channel == other.channel &&
            symbols == other.symbols &&
            fields == other.fields &&
            account_id == other.account_id &&
            keys == other.keys &&
            params == other.params
        end

        alias_method :eql?, :==

        # Generate hash for use as hash key
        #
        # @return [Integer] Hash value
        def hash
          [channel, symbols, fields, account_id, keys, params].hash
        end

        private

        # Validate subscription parameters
        #
        # @raise [ArgumentError] If parameters are invalid
        def validate!
          raise ArgumentError, "channel is required" if @channel.nil? || @channel.empty?

          case @channel
          when "market_data"
            raise ArgumentError, "symbols are required for market_data subscriptions" if @symbols.nil? || @symbols.empty?
          when "portfolio", "orders"
            raise ArgumentError, "account_id is required for #{@channel} subscriptions" if @account_id.nil? || @account_id.empty?
          when "account_summary"
            raise ArgumentError, "account_id is required for account_summary subscriptions" if @account_id.nil? || @account_id.empty?
          end
        end
      end
    end
  end
end
