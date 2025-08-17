# frozen_string_literal: true

module Ibkr
  module WebSocket
    module ValueObjects
      # Value object representing reconnection strategy configuration
      #
      # Encapsulates all reconnection-related parameters, making the
      # reconnection strategy more cohesive and easier to configure.
      #
      # @example Creating a reconnection configuration
      #   config = ReconnectionConfig.new(
      #     max_attempts: 10,
      #     base_delay: 1.0,
      #     max_delay: 300.0,
      #     backoff_multiplier: 2.0,
      #     jitter: true
      #   )
      #
      class ReconnectionConfig
        attr_reader :max_attempts, :base_delay, :max_delay, :backoff_multiplier,
          :jitter, :reconnectable_codes, :non_reconnectable_codes

        # Default configuration values
        DEFAULTS = {
          max_attempts: 10,
          base_delay: 1.0,
          max_delay: 300.0,
          backoff_multiplier: 2.0,
          jitter: true
        }.freeze

        # Default WebSocket close codes that should trigger reconnection
        DEFAULT_RECONNECTABLE_CODES = [
          1006, # Abnormal closure
          1011, # Server error
          1012, # Service restart
          1013, # Try again later
          1014  # Bad gateway
        ].freeze

        # Default WebSocket close codes that should NOT trigger reconnection
        DEFAULT_NON_RECONNECTABLE_CODES = [
          1000, # Normal closure
          1001, # Going away
          1002, # Protocol error
          1003, # Unsupported data
          1007, # Invalid frame payload data
          1008, # Policy violation
          1009, # Message too big
          1010  # Mandatory extension
        ].freeze

        # @param max_attempts [Integer] Maximum reconnection attempts
        # @param base_delay [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay in seconds
        # @param backoff_multiplier [Float] Exponential backoff multiplier
        # @param jitter [Boolean] Whether to add jitter to delays
        # @param reconnectable_codes [Array<Integer>] Codes that trigger reconnection
        # @param non_reconnectable_codes [Array<Integer>] Codes that prevent reconnection
        def initialize(max_attempts: nil, base_delay: nil, max_delay: nil,
          backoff_multiplier: nil, jitter: nil,
          reconnectable_codes: nil, non_reconnectable_codes: nil)
          @max_attempts = (max_attempts || DEFAULTS[:max_attempts]).to_i
          @base_delay = (base_delay || DEFAULTS[:base_delay]).to_f
          @max_delay = (max_delay || DEFAULTS[:max_delay]).to_f
          @backoff_multiplier = (backoff_multiplier || DEFAULTS[:backoff_multiplier]).to_f
          @jitter = jitter.nil? ? DEFAULTS[:jitter] : jitter
          @reconnectable_codes = (reconnectable_codes || DEFAULT_RECONNECTABLE_CODES).freeze
          @non_reconnectable_codes = (non_reconnectable_codes || DEFAULT_NON_RECONNECTABLE_CODES).freeze

          validate!
        end

        # Calculate delay for a specific attempt
        #
        # @param attempt [Integer] Attempt number (1-based)
        # @return [Float] Delay in seconds
        def delay_for_attempt(attempt)
          return 0.1 if attempt <= 0

          # Exponential backoff: base_delay * (backoff_multiplier ^ (attempt - 1))
          delay = @base_delay * (@backoff_multiplier**(attempt - 1))

          # Cap at maximum delay
          delay = [@max_delay, delay].min

          # Apply jitter if enabled
          if @jitter
            # Add ±25% jitter
            jitter_range = delay * 0.25
            jitter_amount = (rand * 2 - 1) * jitter_range
            delay += jitter_amount

            # Re-apply maximum delay cap after jitter
            delay = [@max_delay, delay].min
          end

          # Ensure minimum delay
          [delay, 0.1].max
        end

        # Check if a close code should trigger reconnection
        #
        # @param code [Integer] WebSocket close code
        # @return [Boolean]
        def should_reconnect?(code)
          return true if code.nil? # Unknown close reason, assume reconnectable
          return true if @reconnectable_codes.include?(code)
          return false if @non_reconnectable_codes.include?(code)

          # For unknown codes, default to reconnectable
          true
        end

        # Check if reconnection attempts are exhausted
        #
        # @param attempt [Integer] Current attempt number
        # @return [Boolean]
        def exhausted?(attempt)
          attempt >= @max_attempts
        end

        # Calculate total maximum possible delay
        #
        # @return [Float] Total delay in seconds
        def total_max_delay
          (1..@max_attempts).sum { |i| delay_for_attempt(i) }
        end

        # Convert to hash for serialization
        #
        # @return [Hash] Configuration as hash
        def to_h
          {
            max_attempts: @max_attempts,
            base_delay: @base_delay,
            max_delay: @max_delay,
            backoff_multiplier: @backoff_multiplier,
            jitter: @jitter,
            reconnectable_codes: @reconnectable_codes,
            non_reconnectable_codes: @non_reconnectable_codes
          }
        end

        # Check equality with another configuration
        #
        # @param other [Object] Object to compare with
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(ReconnectionConfig)

          max_attempts == other.max_attempts &&
            base_delay == other.base_delay &&
            max_delay == other.max_delay &&
            backoff_multiplier == other.backoff_multiplier &&
            jitter == other.jitter &&
            reconnectable_codes == other.reconnectable_codes &&
            non_reconnectable_codes == other.non_reconnectable_codes
        end

        alias_method :eql?, :==

        # Generate hash for use as hash key
        #
        # @return [Integer] Hash value
        def hash
          [max_attempts, base_delay, max_delay, backoff_multiplier,
            jitter, reconnectable_codes, non_reconnectable_codes].hash
        end

        # Create a copy with modified values
        #
        # @param attributes [Hash] Attributes to override
        # @return [ReconnectionConfig] New configuration instance
        def with(**attributes)
          self.class.new(
            max_attempts: attributes.fetch(:max_attempts, @max_attempts),
            base_delay: attributes.fetch(:base_delay, @base_delay),
            max_delay: attributes.fetch(:max_delay, @max_delay),
            backoff_multiplier: attributes.fetch(:backoff_multiplier, @backoff_multiplier),
            jitter: attributes.fetch(:jitter, @jitter),
            reconnectable_codes: attributes.fetch(:reconnectable_codes, @reconnectable_codes),
            non_reconnectable_codes: attributes.fetch(:non_reconnectable_codes, @non_reconnectable_codes)
          )
        end

        private

        # Validate configuration parameters
        #
        # @raise [ArgumentError] If configuration is invalid
        def validate!
          raise ArgumentError, "max_attempts must be positive" if @max_attempts <= 0
          raise ArgumentError, "base_delay must be positive" if @base_delay <= 0
          raise ArgumentError, "max_delay must be greater than base_delay" if @max_delay <= @base_delay
          raise ArgumentError, "backoff_multiplier must be >= 1.0" if @backoff_multiplier < 1.0
          raise ArgumentError, "reconnectable_codes must be an array" unless @reconnectable_codes.is_a?(Array)
          raise ArgumentError, "non_reconnectable_codes must be an array" unless @non_reconnectable_codes.is_a?(Array)
        end
      end
    end
  end
end
