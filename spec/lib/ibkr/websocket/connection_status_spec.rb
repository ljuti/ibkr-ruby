# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::WebSocket::ConnectionStatus do
  describe "connection status value object behavior" do
    let(:base_attributes) do
      {
        state: :connected,
        connected: true,
        authenticated: false,
        healthy: true,
        connection_id: "conn_123",
        uptime: 3600,
        last_ping_at: Time.now - 30,
        last_pong_at: Time.now - 25,
        heartbeat_lag: 50,
        websocket_ready_state: 1,
        websocket_nil: false,
        websocket_url: "wss://api.ibkr.com/ws",
        eventmachine_running: true,
        has_errors: false
      }
    end

    context "when creating a connection status with minimal required attributes" do
      let(:minimal_attributes) do
        {
          state: :disconnected,
          connected: false,
          authenticated: false,
          healthy: false
        }
      end

      it "creates a valid instance with default values for optional attributes" do
        # Given minimal connection state information
        # When creating a ConnectionStatus instance
        status = described_class.new(**minimal_attributes)

        # Then it should have the required state
        expect(status.state).to eq(:disconnected)
        expect(status.connected).to be(false)
        expect(status.authenticated).to be(false)
        expect(status.healthy).to be(false)

        # And optional attributes should have sensible defaults
        expect(status.connection_id).to be_nil
        expect(status.uptime).to be_nil
        expect(status.websocket_nil).to be(true)
        expect(status.eventmachine_running).to be(false)
        expect(status.has_errors).to be(false)
      end
    end

    context "when creating a connection status with full attributes" do
      it "preserves all provided connection state information" do
        # Given complete connection state data from WebSocket client
        # When creating a ConnectionStatus instance
        status = described_class.new(**base_attributes)

        # Then all attributes should be accessible
        expect(status.state).to eq(:connected)
        expect(status.connected).to be(true)
        expect(status.authenticated).to be(false)
        expect(status.healthy).to be(true)
        expect(status.connection_id).to eq("conn_123")
        expect(status.uptime).to eq(3600)
        expect(status.websocket_ready_state).to eq(1)
        expect(status.websocket_url).to eq("wss://api.ibkr.com/ws")
        expect(status.eventmachine_running).to be(true)
      end

      it "correctly handles timestamp attributes for heartbeat monitoring" do
        now = Time.now
        attributes = base_attributes.merge(
          last_ping_at: now - 60,
          last_pong_at: now - 55,
          heartbeat_lag: 100
        )

        status = described_class.new(**attributes)

        expect(status.last_ping_at).to eq(now - 60)
        expect(status.last_pong_at).to eq(now - 55)
        expect(status.heartbeat_lag).to eq(100)
      end
    end
  end

  describe "operational status checks" do
    let(:base_attributes) do
      {
        state: :connected,
        connected: true,
        authenticated: false,
        healthy: true,
        connection_id: "conn_123",
        uptime: 3600,
        last_ping_at: Time.now - 30,
        last_pong_at: Time.now - 25,
        heartbeat_lag: 50,
        websocket_ready_state: 1,
        websocket_nil: false,
        websocket_url: "wss://api.ibkr.com/ws",
        eventmachine_running: true,
        has_errors: false
      }
    end

    context "when connection is operational" do
      let(:operational_attributes) do
        {
          state: :authenticated,
          connected: true,
          authenticated: true,
          healthy: true,
          has_errors: false
        }
      end

      it "reports as operational when connected, healthy and has no errors" do
        # Given a fully operational WebSocket connection
        # When checking operational status
        status = described_class.new(**operational_attributes)

        # Then it should report as operational
        expect(status.operational?).to be(true)
      end

      it "reports as ready for streaming when authenticated and operational" do
        # Given an authenticated and operational connection
        # When checking streaming readiness
        status = described_class.new(**operational_attributes)

        # Then it should be ready for data streaming
        expect(status.ready_for_streaming?).to be(true)
      end
    end

    context "when connection has issues" do
      it "reports as not operational when disconnected" do
        attributes = base_attributes.merge(
          connected: false,
          healthy: true,
          has_errors: false
        )

        # Given a disconnected WebSocket
        # When checking operational status
        status = described_class.new(**attributes)

        # Then it should not be operational
        expect(status.operational?).to be(false)
        expect(status.ready_for_streaming?).to be(false)
      end

      it "reports as not operational when unhealthy" do
        attributes = base_attributes.merge(
          connected: true,
          healthy: false,
          has_errors: false
        )

        # Given an unhealthy connection
        # When checking operational status
        status = described_class.new(**attributes)

        # Then it should not be operational
        expect(status.operational?).to be(false)
      end

      it "reports as not operational when has errors" do
        attributes = base_attributes.merge(
          connected: true,
          healthy: true,
          has_errors: true
        )

        # Given a connection with errors
        # When checking operational status
        status = described_class.new(**attributes)

        # Then it should not be operational
        expect(status.operational?).to be(false)
      end

      it "reports as not ready for streaming when not authenticated" do
        attributes = base_attributes.merge(
          connected: true,
          authenticated: false,
          healthy: true,
          has_errors: false
        )

        # Given a connected but unauthenticated connection
        # When checking streaming readiness
        status = described_class.new(**attributes)

        # Then it should be operational but not ready for streaming
        expect(status.operational?).to be(true)
        expect(status.ready_for_streaming?).to be(false)
      end
    end
  end

  describe "human-readable status summaries" do
    context "for different connection states" do
      it "provides clear summary for disconnected state" do
        # Given a disconnected WebSocket
        attributes = {state: :disconnected, connected: false, authenticated: false, healthy: false}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should provide clear disconnected message
        expect(status.summary).to eq("Disconnected")
        expect(status.to_s).to eq("Disconnected")
      end

      it "provides clear summary for connecting state" do
        # Given a WebSocket in connecting state
        attributes = {state: :connecting, connected: false, authenticated: false, healthy: false}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should indicate connection in progress
        expect(status.summary).to eq("Connecting...")
      end

      it "provides clear summary for connected but not authenticated state" do
        # Given a connected but unauthenticated WebSocket
        attributes = {state: :connected, connected: true, authenticated: false, healthy: true}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should indicate connection without authentication
        expect(status.summary).to eq("Connected (not authenticated)")
      end

      it "provides clear summary for authenticating state" do
        # Given a WebSocket in authentication process
        attributes = {state: :authenticating, connected: true, authenticated: false, healthy: true}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should indicate authentication in progress
        expect(status.summary).to eq("Authenticating...")
      end

      it "provides clear summary for fully ready state" do
        # Given a fully authenticated and healthy WebSocket
        attributes = {state: :authenticated, connected: true, authenticated: true, healthy: true}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should indicate ready state
        expect(status.summary).to eq("Ready (authenticated and healthy)")
      end

      it "provides clear summary for authenticated but unhealthy state" do
        # Given an authenticated but unhealthy WebSocket
        attributes = {state: :authenticated, connected: true, authenticated: true, healthy: false}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should indicate authentication but health issues
        expect(status.summary).to eq("Authenticated but unhealthy")
      end

      it "provides clear summary for error state" do
        # Given a WebSocket in error state
        attributes = {state: :error, connected: false, authenticated: false, healthy: false}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should indicate error condition
        expect(status.summary).to eq("Error state")
      end

      it "provides clear summary for reconnecting state" do
        # Given a WebSocket attempting to reconnect
        attributes = {state: :reconnecting, connected: false, authenticated: false, healthy: false}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should indicate reconnection attempt
        expect(status.summary).to eq("Reconnecting...")
      end

      it "handles unknown states gracefully" do
        # Given a WebSocket with an unknown state
        attributes = {state: :unknown_state, connected: false, authenticated: false, healthy: false}
        status = described_class.new(**attributes)

        # When getting status summary
        # Then it should gracefully handle unknown state
        expect(status.summary).to eq("Unknown state: unknown_state")
      end
    end
  end

  describe "hash representation for compatibility" do
    let(:base_attributes) do
      {
        state: :connected,
        connected: true,
        authenticated: false,
        healthy: true,
        connection_id: "conn_123",
        uptime: 3600,
        last_ping_at: Time.now - 30,
        last_pong_at: Time.now - 25,
        heartbeat_lag: 50,
        websocket_ready_state: 1,
        websocket_nil: false,
        websocket_url: "wss://api.ibkr.com/ws",
        eventmachine_running: true,
        has_errors: false
      }
    end

    it "converts to hash with all attributes and computed values" do
      # Given a WebSocket connection status
      attributes = base_attributes.merge(
        state: :authenticated,
        authenticated: true,
        healthy: true,
        has_errors: false
      )
      status = described_class.new(**attributes)

      # When converting to hash
      hash = status.to_h

      # Then it should include all attributes
      expect(hash).to include(
        state: :authenticated,
        connected: true,
        authenticated: true,
        healthy: true,
        connection_id: "conn_123",
        uptime: 3600,
        websocket_ready_state: 1,
        websocket_url: "wss://api.ibkr.com/ws",
        eventmachine_running: true,
        has_errors: false
      )

      # And computed values for convenience
      expect(hash).to include(
        operational: true,
        ready_for_streaming: true,
        summary: "Ready (authenticated and healthy)"
      )
    end

    it "includes timestamp attributes in hash representation" do
      now = Time.now
      attributes = base_attributes.merge(
        last_ping_at: now - 30,
        last_pong_at: now - 25,
        heartbeat_lag: 50
      )
      status = described_class.new(**attributes)

      hash = status.to_h

      expect(hash[:last_ping_at]).to eq(now - 30)
      expect(hash[:last_pong_at]).to eq(now - 25)
      expect(hash[:heartbeat_lag]).to eq(50)
    end
  end

  describe "debug and inspection methods" do
    let(:base_attributes) do
      {
        state: :connected,
        connected: true,
        authenticated: false,
        healthy: true,
        connection_id: "conn_123",
        uptime: 3600,
        last_ping_at: Time.now - 30,
        last_pong_at: Time.now - 25,
        heartbeat_lag: 50,
        websocket_ready_state: 1,
        websocket_nil: false,
        websocket_url: "wss://api.ibkr.com/ws",
        eventmachine_running: true,
        has_errors: false
      }
    end

    it "provides meaningful string representation" do
      # Given a connection status
      attributes = {state: :connected, connected: true, authenticated: false, healthy: true}
      status = described_class.new(**attributes)

      # When converting to string
      # Then it should use the summary
      expect(status.to_s).to eq(status.summary)
      expect(status.to_s).to eq("Connected (not authenticated)")
    end

    it "provides detailed inspect representation" do
      # Given a connection status with ID
      attributes = base_attributes.merge(
        state: :authenticated,
        connection_id: "conn_xyz_789"
      )
      status = described_class.new(**attributes)

      # When inspecting the object
      inspect_output = status.inspect

      # Then it should include class name, summary, and connection ID
      expect(inspect_output).to include("Ibkr::WebSocket::ConnectionStatus")
      expect(inspect_output).to include("Ready (authenticated and healthy)")
      expect(inspect_output).to include("conn_xyz_789")
      expect(inspect_output).to match(/#<.*>/)
    end

    it "handles nil connection ID in inspect" do
      # Given a connection status without ID
      attributes = base_attributes.merge(
        state: :connecting,
        connection_id: nil
      )
      status = described_class.new(**attributes)

      # When inspecting the object
      inspect_output = status.inspect

      # Then it should handle nil connection ID gracefully
      expect(inspect_output).to include("connection_id=")
      expect(inspect_output).to include("Connecting...")
    end
  end

  describe "edge cases and boundary conditions" do
    let(:base_attributes) do
      {
        state: :connected,
        connected: true,
        authenticated: false,
        healthy: true,
        connection_id: "conn_123",
        uptime: 3600,
        last_ping_at: Time.now - 30,
        last_pong_at: Time.now - 25,
        heartbeat_lag: 50,
        websocket_ready_state: 1,
        websocket_nil: false,
        websocket_url: "wss://api.ibkr.com/ws",
        eventmachine_running: true,
        has_errors: false
      }
    end

    context "when handling nil values" do
      it "handles all optional attributes as nil" do
        # Given a status with minimal data
        attributes = {
          state: :disconnected,
          connected: false,
          authenticated: false,
          healthy: false,
          connection_id: nil,
          uptime: nil,
          last_ping_at: nil,
          last_pong_at: nil,
          heartbeat_lag: nil,
          websocket_ready_state: nil,
          websocket_url: nil
        }

        # When creating status
        # Then it should handle nil values gracefully
        expect { described_class.new(**attributes) }.not_to raise_error

        status = described_class.new(**attributes)
        expect(status.connection_id).to be_nil
        expect(status.uptime).to be_nil
        expect(status.websocket_url).to be_nil
      end
    end

    context "when handling zero and negative values" do
      it "handles zero uptime" do
        # Given a newly connected WebSocket
        attributes = base_attributes.merge(uptime: 0)
        status = described_class.new(**attributes)

        # When checking uptime
        # Then it should handle zero uptime
        expect(status.uptime).to eq(0)
      end

      it "handles negative heartbeat lag (clock skew)" do
        # Given a connection with clock skew
        attributes = base_attributes.merge(heartbeat_lag: -10)
        status = described_class.new(**attributes)

        # When checking heartbeat lag
        # Then it should preserve negative values for clock skew scenarios
        expect(status.heartbeat_lag).to eq(-10)
      end
    end

    context "when handling boolean flag combinations" do
      it "correctly handles all false flags" do
        # Given a completely failed connection
        attributes = {
          state: :error,
          connected: false,
          authenticated: false,
          healthy: false,
          websocket_nil: true,
          eventmachine_running: false,
          has_errors: true
        }
        status = described_class.new(**attributes)

        # When checking operational status
        # Then all checks should be false
        expect(status.operational?).to be(false)
        expect(status.ready_for_streaming?).to be(false)
        expect(status.connected).to be(false)
        expect(status.authenticated).to be(false)
        expect(status.healthy).to be(false)
      end

      it "correctly handles mixed boolean states" do
        # Given a partially working connection
        attributes = {
          state: :connected,
          connected: true,
          authenticated: false,
          healthy: true,
          websocket_nil: false,
          eventmachine_running: true,
          has_errors: false
        }
        status = described_class.new(**attributes)

        # When checking status
        # Then it should reflect partial functionality
        expect(status.operational?).to be(true)
        expect(status.ready_for_streaming?).to be(false) # Not authenticated
        expect(status.connected).to be(true)
        expect(status.authenticated).to be(false)
      end
    end

    context "when handling different websocket ready states" do
      [0, 1, 2, 3].each do |ready_state|
        it "preserves websocket ready state #{ready_state}" do
          # Given a WebSocket with specific ready state
          attributes = base_attributes.merge(websocket_ready_state: ready_state)
          status = described_class.new(**attributes)

          # When accessing ready state
          # Then it should preserve the exact value
          expect(status.websocket_ready_state).to eq(ready_state)
        end
      end
    end
  end

  describe "real-world WebSocket scenarios" do
    context "when connection is establishing" do
      it "represents initial connection attempt" do
        # Given a WebSocket starting to connect
        status = described_class.new(
          state: :connecting,
          connected: false,
          authenticated: false,
          healthy: false,
          websocket_ready_state: 0, # CONNECTING
          websocket_nil: true,
          eventmachine_running: true
        )

        # When checking status during connection
        # Then it should reflect connection attempt
        expect(status.summary).to eq("Connecting...")
        expect(status.operational?).to be(false)
        expect(status.ready_for_streaming?).to be(false)
      end
    end

    context "when connection is established but not authenticated" do
      it "represents connected state awaiting authentication" do
        # Given a WebSocket that connected successfully
        status = described_class.new(
          state: :connected,
          connected: true,
          authenticated: false,
          healthy: true,
          connection_id: "ws_conn_12345",
          websocket_ready_state: 1, # OPEN
          websocket_nil: false,
          websocket_url: "wss://api.ibkr.com/ws/streaming",
          eventmachine_running: true,
          uptime: 15
        )

        # When checking status after connection
        # Then it should reflect connected but unauthenticated state
        expect(status.summary).to eq("Connected (not authenticated)")
        expect(status.operational?).to be(true)
        expect(status.ready_for_streaming?).to be(false)
        expect(status.connected).to be(true)
        expect(status.connection_id).to eq("ws_conn_12345")
      end
    end

    context "when connection is fully ready for streaming" do
      it "represents production-ready streaming connection" do
        # Given a fully authenticated and healthy WebSocket
        now = Time.now
        status = described_class.new(
          state: :authenticated,
          connected: true,
          authenticated: true,
          healthy: true,
          connection_id: "stream_session_67890",
          uptime: 3600,
          last_ping_at: now - 30,
          last_pong_at: now - 28,
          heartbeat_lag: 45,
          websocket_ready_state: 1,
          websocket_nil: false,
          websocket_url: "wss://api.ibkr.com/ws/market_data",
          eventmachine_running: true,
          has_errors: false
        )

        # When checking fully ready connection
        # Then it should be ready for all operations
        expect(status.summary).to eq("Ready (authenticated and healthy)")
        expect(status.operational?).to be(true)
        expect(status.ready_for_streaming?).to be(true)
        expect(status.heartbeat_lag).to eq(45)
        expect(status.uptime).to eq(3600)
      end
    end

    context "when connection encounters errors" do
      it "represents error state with diagnostic information" do
        # Given a WebSocket that encountered errors
        status = described_class.new(
          state: :error,
          connected: false,
          authenticated: false,
          healthy: false,
          connection_id: "failed_conn_999",
          websocket_ready_state: 3, # CLOSED
          websocket_nil: true,
          eventmachine_running: false,
          has_errors: true,
          uptime: 45 # Was connected for 45 seconds before failing
        )

        # When checking error state
        # Then it should reflect failure with diagnostic info
        expect(status.summary).to eq("Error state")
        expect(status.operational?).to be(false)
        expect(status.ready_for_streaming?).to be(false)
        expect(status.has_errors).to be(true)
        expect(status.connection_id).to eq("failed_conn_999")
      end
    end

    context "when connection is reconnecting" do
      it "represents reconnection attempt with previous session info" do
        # Given a WebSocket attempting to reconnect
        status = described_class.new(
          state: :reconnecting,
          connected: false,
          authenticated: false,
          healthy: false,
          connection_id: "reconnect_attempt_3",
          websocket_ready_state: 0,
          websocket_nil: true,
          websocket_url: "wss://api.ibkr.com/ws/streaming",
          eventmachine_running: true,
          has_errors: false,
          uptime: nil # No uptime during reconnection
        )

        # When checking reconnection state
        # Then it should reflect reconnection attempt
        expect(status.summary).to eq("Reconnecting...")
        expect(status.operational?).to be(false)
        expect(status.ready_for_streaming?).to be(false)
        expect(status.state).to eq(:reconnecting)
      end
    end
  end
end
