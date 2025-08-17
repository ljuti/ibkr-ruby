# frozen_string_literal: true

require "eventmachine"

module Ibkr
  module WebSocket
    # Reconnection strategy implementing exponential backoff with jitter
    # for robust WebSocket connection recovery.
    #
    # Features:
    # - Exponential backoff with configurable parameters
    # - Jitter to prevent thundering herd problems
    # - Maximum attempt limits
    # - Automatic scheduling and cancellation
    # - Connection closure code analysis
    # - Server guidance handling
    # - Statistics tracking
    #
    class ReconnectionStrategy
      include Ibkr::WebSocket::EventEmitter

      defines_events :reconnection_scheduled, :reconnection_attempted, 
                     :reconnection_succeeded, :reconnection_failed, :max_attempts_reached

      # WebSocket close codes that should trigger automatic reconnection
      RECONNECTABLE_CODES = [
        1006, # Abnormal closure
        1011, # Server error  
        1012, # Service restart
        1013, # Try again later
        1014  # Bad gateway
      ].freeze

      # WebSocket close codes that should NOT trigger reconnection
      NON_RECONNECTABLE_CODES = [
        1000, # Normal closure
        1001, # Going away
        1002, # Protocol error
        1003, # Unsupported data
        1007, # Invalid frame payload data
        1008, # Policy violation
        1009, # Message too big
        1010  # Mandatory extension
      ].freeze

      attr_reader :max_attempts, :base_delay, :max_delay, :backoff_multiplier,
                  :reconnect_attempts, :last_attempt_at, :last_successful_connection_at,
                  :last_failure_reason, :automatic_reconnection_enabled

      # @param websocket_client [Ibkr::WebSocket::Client] WebSocket client to reconnect
      # @param config [Hash] Configuration options
      # @option config [Integer] :max_attempts Maximum reconnection attempts (10)
      # @option config [Float] :base_delay Base delay in seconds (1.0)
      # @option config [Float] :max_delay Maximum delay in seconds (300.0)
      # @option config [Float] :backoff_multiplier Exponential backoff multiplier (2.0)
      # @option config [Boolean] :jitter Enable jitter to prevent thundering herd (true)
      def initialize(websocket_client, config = {})
        @websocket_client = websocket_client
        @max_attempts = config.fetch(:max_attempts, 10)
        @base_delay = config.fetch(:base_delay, 1.0)
        @max_delay = config.fetch(:max_delay, 300.0)
        @backoff_multiplier = config.fetch(:backoff_multiplier, 2.0)
        @jitter_enabled = config.fetch(:jitter, true)
        
        validate_configuration!
        
        @reconnect_attempts = 0
        @last_attempt_at = nil
        @last_successful_connection_at = nil
        @last_failure_reason = nil
        @automatic_reconnection_enabled = false
        @scheduled_timer = nil
        @statistics = {
          total_attempts: 0,
          successful_reconnections: 0,
          failed_attempts: 0
        }
        
        initialize_events
      end

      # Check if reconnection is allowed
      #
      # @return [Boolean] True if reconnection attempts are allowed
      def can_reconnect?
        @reconnect_attempts < @max_attempts
      end

      # Check if jitter is enabled
      #
      # @return [Boolean] True if jitter is enabled
      def jitter_enabled?
        @jitter_enabled
      end

      # Calculate next reconnection delay with exponential backoff
      #
      # @param attempt [Integer] Attempt number (1-based)
      # @return [Float] Delay in seconds
      def next_reconnect_delay(attempt)
        # Exponential backoff: base_delay * (backoff_multiplier ^ (attempt - 1))
        delay = @base_delay * (@backoff_multiplier ** (attempt - 1))
        
        # Cap at maximum delay
        delay = [@max_delay, delay].min
        
        # Apply jitter if enabled
        if @jitter_enabled
          # Add ±25% jitter
          jitter_range = delay * 0.25
          jitter = (rand * 2 - 1) * jitter_range
          delay += jitter
          
          # Re-apply maximum delay cap after jitter
          delay = [@max_delay, delay].min
        end
        
        # Ensure minimum delay
        [delay, 0.1].max
      end
      
      # Alias for compatibility with shared examples
      alias_method :max_reconnect_delay, :max_delay

      # Attempt reconnection
      #
      # @return [Boolean] True if reconnection succeeded
      # @raise [ReconnectionError] If max attempts exceeded or connection fails
      def attempt_reconnect
        unless can_reconnect?
          raise ReconnectionError.max_attempts_exceeded(
            @max_attempts,
            context: {
              total_attempts: @statistics[:total_attempts],
              failed_attempts: @statistics[:failed_attempts]
            }
          )
        end

        @reconnect_attempts += 1
        @last_attempt_at = Time.now
        @statistics[:total_attempts] += 1
        
        emit(:reconnection_attempted, attempt: @reconnect_attempts)
        
        begin
          @websocket_client.connect
          
          # Verify connection succeeded
          if @websocket_client.connected?
            handle_successful_reconnection
            true
          else
            handle_failed_reconnection("Connection not established")
            false
          end
        rescue => e
          handle_failed_reconnection(e.message)
          raise ReconnectionError.new(
            "Reconnection attempt #{@reconnect_attempts} failed: #{e.message}",
            context: { 
              attempt: @reconnect_attempts,
              max_attempts: @max_attempts
            },
            cause: e
          )
        end
      end

      # Schedule automatic reconnection with calculated delay
      #
      # @return [Boolean] True if scheduled successfully
      def schedule_reconnection
        return false if @scheduled_timer # Already scheduled
        return false unless can_reconnect?

        delay = next_reconnect_delay(@reconnect_attempts + 1)
        
        @scheduled_timer = EventMachine.add_timer(delay) do
          @scheduled_timer = nil
          
          begin
            attempt_reconnect
          rescue ReconnectionError => e
            emit(:reconnection_failed, error: e, final: !can_reconnect?)
            
            # Schedule next attempt if possible
            if can_reconnect?
              schedule_reconnection
            else
              emit(:max_attempts_reached, total_attempts: @statistics[:total_attempts])
              disable_automatic_reconnection
            end
          end
        end
        
        emit(:reconnection_scheduled, delay: delay, attempt: @reconnect_attempts + 1)
        true
      end

      # Cancel scheduled reconnection
      #
      # @return [Boolean] True if cancellation successful
      def cancel_scheduled_reconnection
        if @scheduled_timer
          @scheduled_timer.cancel
          @scheduled_timer = nil
          true
        else
          false
        end
      end

      # Reset reconnection attempt counter
      #
      # @return [void]
      def reset_reconnect_attempts
        @reconnect_attempts = 0
        @last_failure_reason = nil
      end

      # Enable automatic reconnection
      #
      # @return [void]
      def enable_automatic_reconnection
        @automatic_reconnection_enabled = true
      end

      # Disable automatic reconnection
      #
      # @return [void]
      def disable_automatic_reconnection
        @automatic_reconnection_enabled = false
        cancel_scheduled_reconnection
      end

      # Check if automatic reconnection is enabled
      #
      # @return [Boolean] True if automatic reconnection is enabled
      def automatic_reconnection_enabled?
        @automatic_reconnection_enabled
      end

      # Handle connection lost event
      #
      # @param code [Integer] WebSocket close code
      # @param reason [String] Close reason
      # @return [void]
      def handle_connection_lost(code: nil, reason: nil)
        return unless @automatic_reconnection_enabled
        return unless should_reconnect?(code)

        schedule_reconnection
      end

      # Handle connection closed event
      #
      # @param code [Integer] WebSocket close code
      # @param reason [String] Close reason
      # @return [void]
      def handle_connection_closed(code:, reason:)
        if should_reconnect?(code) && @automatic_reconnection_enabled
          handle_connection_lost(code: code, reason: reason)
        end
      end

      # Check if reconnection should be attempted based on close code
      #
      # @param code [Integer] WebSocket close code
      # @return [Boolean] True if reconnection should be attempted
      def should_reconnect?(code)
        return true if code.nil? # Unknown close reason, assume reconnectable
        return true if RECONNECTABLE_CODES.include?(code)
        return false if NON_RECONNECTABLE_CODES.include?(code)
        
        # For unknown codes, default to reconnectable
        true
      end

      # Apply server guidance for reconnection strategy
      #
      # @param guidance [Hash] Server-provided reconnection guidance
      # @option guidance [Integer] :retry_after Minimum delay before retry
      # @option guidance [Integer] :max_attempts Maximum attempts allowed
      # @return [void]
      def apply_server_guidance(guidance)
        if guidance[:retry_after]
          @base_delay = [guidance[:retry_after], @base_delay].max
        end
        
        if guidance[:max_attempts]
          @max_attempts = guidance[:max_attempts]
        end
      end

      # Handle successful reconnection
      #
      # @return [void]
      def handle_successful_reconnection
        @last_successful_connection_at = Time.now
        @statistics[:successful_reconnections] += 1
        
        reset_reconnect_attempts
        emit(:reconnection_succeeded, 
             attempts: @statistics[:total_attempts],
             success_time: @last_successful_connection_at)
      end

      # Get time since last reconnection attempt
      #
      # @return [Float, nil] Seconds since last attempt, or nil if no attempts
      def time_since_last_attempt
        return nil unless @last_attempt_at
        Time.now - @last_attempt_at
      end

      # Get reconnection statistics
      #
      # @return [Hash] Statistics about reconnection attempts
      def reconnection_statistics
        total = @statistics[:total_attempts]
        successful = @statistics[:successful_reconnections]
        failed = @statistics[:failed_attempts]
        
        {
          total_attempts: total,
          successful_reconnections: successful,
          failed_attempts: failed,
          success_rate: total > 0 ? successful.to_f / total : 0.0,
          failure_rate: total > 0 ? failed.to_f / total : 0.0,
          average_attempts_to_success: successful > 0 ? total.to_f / successful : 0.0,
          current_streak: @reconnect_attempts,
          last_success: @last_successful_connection_at,
          last_failure_reason: @last_failure_reason
        }
      end

      # Clean up resources
      #
      # @return [void]
      def cleanup
        cancel_scheduled_reconnection
        disable_automatic_reconnection
      end

      private

      # Validate configuration parameters
      #
      # @raise [ArgumentError] If configuration is invalid
      def validate_configuration!
        raise ArgumentError, "max_attempts must be positive" if @max_attempts <= 0
        raise ArgumentError, "base_delay must be positive" if @base_delay <= 0
        raise ArgumentError, "max_delay must be greater than base_delay" if @max_delay <= @base_delay
        raise ArgumentError, "backoff_multiplier must be >= 1.0" if @backoff_multiplier < 1.0
      end

      # Handle failed reconnection attempt
      #
      # @param reason [String] Failure reason
      # @return [void]
      def handle_failed_reconnection(reason)
        @last_failure_reason = reason
        @statistics[:failed_attempts] += 1
        
        emit(:reconnection_failed, 
             attempt: @reconnect_attempts,
             reason: reason,
             final: !can_reconnect?)
      end
    end
  end
end