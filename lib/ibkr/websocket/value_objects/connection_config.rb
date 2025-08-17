# frozen_string_literal: true

module Ibkr
  module WebSocket
    module ValueObjects
      # Value object representing WebSocket connection configuration
      #
      # Encapsulates all connection-related parameters, reducing coupling
      # between classes and making configuration management cleaner.
      #
      # @example Creating a connection configuration
      #   config = ConnectionConfig.new(
      #     endpoint: "wss://localhost:5000/ws",
      #     heartbeat_interval: 30,
      #     connection_timeout: 60,
      #     max_message_size: 1024 * 1024
      #   )
      #
      class ConnectionConfig
        attr_reader :endpoint, :heartbeat_interval, :connection_timeout,
          :max_message_size, :ping_interval, :pong_timeout,
          :headers, :options

        # Default configuration values
        DEFAULTS = {
          heartbeat_interval: 30,
          connection_timeout: 60,
          ping_interval: 30,
          pong_timeout: 10,
          max_message_size: 10 * 1024 * 1024 # 10MB
        }.freeze

        # @param endpoint [String] WebSocket endpoint URL
        # @param heartbeat_interval [Integer] Heartbeat interval in seconds
        # @param connection_timeout [Integer] Connection timeout in seconds
        # @param max_message_size [Integer] Maximum message size in bytes
        # @param ping_interval [Integer] Ping interval in seconds
        # @param pong_timeout [Integer] Pong timeout in seconds
        # @param headers [Hash] Additional headers for connection
        # @param options [Hash] Additional options
        def initialize(endpoint:, heartbeat_interval: nil, connection_timeout: nil,
          max_message_size: nil, ping_interval: nil, pong_timeout: nil,
          headers: {}, **options)
          @endpoint = endpoint.freeze
          @heartbeat_interval = (heartbeat_interval || DEFAULTS[:heartbeat_interval]).to_i
          @connection_timeout = (connection_timeout || DEFAULTS[:connection_timeout]).to_i
          @max_message_size = (max_message_size || DEFAULTS[:max_message_size]).to_i
          @ping_interval = (ping_interval || DEFAULTS[:ping_interval]).to_i
          @pong_timeout = (pong_timeout || DEFAULTS[:pong_timeout]).to_i
          @headers = headers.freeze
          @options = options.freeze

          validate!
        end

        # Convert to hash for use in connection setup
        #
        # @return [Hash] Configuration as hash
        def to_h
          {
            endpoint: @endpoint,
            heartbeat_interval: @heartbeat_interval,
            connection_timeout: @connection_timeout,
            max_message_size: @max_message_size,
            ping_interval: @ping_interval,
            pong_timeout: @pong_timeout,
            headers: @headers
          }.merge(@options)
        end

        # Check if connection is secure (WSS)
        #
        # @return [Boolean]
        def secure?
          @endpoint.start_with?("wss://")
        end

        # Get the host from the endpoint
        #
        # @return [String] Host portion of the endpoint
        def host
          uri = URI.parse(@endpoint)
          uri.host
        rescue URI::InvalidURIError
          nil
        end

        # Get the port from the endpoint
        #
        # @return [Integer] Port number
        def port
          uri = URI.parse(@endpoint)
          uri.port
        rescue URI::InvalidURIError
          nil
        end

        # Check if heartbeat is enabled
        #
        # @return [Boolean]
        def heartbeat_enabled?
          @heartbeat_interval > 0
        end

        # Calculate total timeout for operations
        #
        # @return [Integer] Total timeout in seconds
        def total_timeout
          @connection_timeout + @pong_timeout
        end

        # Check equality with another configuration
        #
        # @param other [Object] Object to compare with
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(ConnectionConfig)

          endpoint == other.endpoint &&
            heartbeat_interval == other.heartbeat_interval &&
            connection_timeout == other.connection_timeout &&
            max_message_size == other.max_message_size &&
            ping_interval == other.ping_interval &&
            pong_timeout == other.pong_timeout &&
            headers == other.headers &&
            options == other.options
        end

        alias_method :eql?, :==

        # Generate hash for use as hash key
        #
        # @return [Integer] Hash value
        def hash
          [endpoint, heartbeat_interval, connection_timeout, max_message_size,
            ping_interval, pong_timeout, headers, options].hash
        end

        # Create a copy with modified values
        #
        # @param attributes [Hash] Attributes to override
        # @return [ConnectionConfig] New configuration instance
        def with(**attributes)
          self.class.new(
            endpoint: attributes.fetch(:endpoint, @endpoint),
            heartbeat_interval: attributes.fetch(:heartbeat_interval, @heartbeat_interval),
            connection_timeout: attributes.fetch(:connection_timeout, @connection_timeout),
            max_message_size: attributes.fetch(:max_message_size, @max_message_size),
            ping_interval: attributes.fetch(:ping_interval, @ping_interval),
            pong_timeout: attributes.fetch(:pong_timeout, @pong_timeout),
            headers: attributes.fetch(:headers, @headers),
            **attributes.except(:endpoint, :heartbeat_interval, :connection_timeout,
              :max_message_size, :ping_interval, :pong_timeout, :headers)
          )
        end

        private

        # Validate configuration parameters
        #
        # @raise [ArgumentError] If configuration is invalid
        def validate!
          raise ArgumentError, "endpoint is required" if @endpoint.nil? || @endpoint.empty?
          raise ArgumentError, "endpoint must be a valid WebSocket URL" unless @endpoint.match?(/^wss?:\/\//)
          raise ArgumentError, "heartbeat_interval must be non-negative" if @heartbeat_interval < 0
          raise ArgumentError, "connection_timeout must be positive" if @connection_timeout <= 0
          raise ArgumentError, "max_message_size must be positive" if @max_message_size <= 0
          raise ArgumentError, "ping_interval must be non-negative" if @ping_interval < 0
          raise ArgumentError, "pong_timeout must be positive" if @pong_timeout <= 0
        end
      end
    end
  end
end
