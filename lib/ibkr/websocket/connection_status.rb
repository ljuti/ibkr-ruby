# frozen_string_literal: true

module Ibkr
  module WebSocket
    # Value object representing WebSocket connection status
    # Replaces complex hash returns with structured, typed data
    class ConnectionStatus
      attr_reader :state, :connected, :authenticated, :healthy, :connection_id,
                  :uptime, :last_ping_at, :last_pong_at, :heartbeat_lag,
                  :websocket_ready_state, :websocket_nil, :websocket_url,
                  :eventmachine_running, :has_errors

      def initialize(
        state:,
        connected:,
        authenticated:,
        healthy:,
        connection_id: nil,
        uptime: nil,
        last_ping_at: nil,
        last_pong_at: nil,
        heartbeat_lag: nil,
        websocket_ready_state: nil,
        websocket_nil: true,
        websocket_url: nil,
        eventmachine_running: false,
        has_errors: false
      )
        @state = state
        @connected = connected
        @authenticated = authenticated
        @healthy = healthy
        @connection_id = connection_id
        @uptime = uptime
        @last_ping_at = last_ping_at
        @last_pong_at = last_pong_at
        @heartbeat_lag = heartbeat_lag
        @websocket_ready_state = websocket_ready_state
        @websocket_nil = websocket_nil
        @websocket_url = websocket_url
        @eventmachine_running = eventmachine_running
        @has_errors = has_errors
      end

      # Check if connection is in a good state
      #
      # @return [Boolean] True if connected and healthy
      def operational?
        connected && healthy && !has_errors
      end

      # Check if ready for data streaming
      #
      # @return [Boolean] True if authenticated and operational
      def ready_for_streaming?
        authenticated && operational?
      end

      # Get human-readable status summary
      #
      # @return [String] Status summary
      def summary
        case state
        when :disconnected
          "Disconnected"
        when :connecting
          "Connecting..."
        when :connected
          "Connected (not authenticated)"
        when :authenticating
          "Authenticating..."
        when :authenticated
          if healthy
            "Ready (authenticated and healthy)"
          else
            "Authenticated but unhealthy"
          end
        when :error
          "Error state"
        when :reconnecting
          "Reconnecting..."
        else
          "Unknown state: #{state}"
        end
      end

      # Convert to hash for backward compatibility
      #
      # @return [Hash] Hash representation
      def to_h
        {
          state: state,
          connected: connected,
          authenticated: authenticated,
          healthy: healthy,
          connection_id: connection_id,
          uptime: uptime,
          last_ping_at: last_ping_at,
          last_pong_at: last_pong_at,
          heartbeat_lag: heartbeat_lag,
          websocket_ready_state: websocket_ready_state,
          websocket_nil: websocket_nil,
          websocket_url: websocket_url,
          eventmachine_running: eventmachine_running,
          has_errors: has_errors,
          operational: operational?,
          ready_for_streaming: ready_for_streaming?,
          summary: summary
        }
      end

      # String representation
      #
      # @return [String] String representation
      def to_s
        summary
      end

      # Inspect representation
      #
      # @return [String] Detailed string representation
      def inspect
        "#<#{self.class.name} #{summary} connection_id=#{connection_id}>"
      end
    end
  end
end