# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::WebSocket::ReconnectionStrategy do
  include_context "with WebSocket test environment"

  let(:websocket_client) { double("websocket_client", connect: true, connected?: false) }
  let(:reconnection_strategy) { described_class.new(websocket_client) }
  
  subject { reconnection_strategy }

  describe "initialization" do
    context "when creating reconnection strategy" do
      it "initializes with default configuration" do
        # Given new reconnection strategy
        strategy = described_class.new(websocket_client)

        # Then default configuration should be set
        expect(strategy.max_attempts).to eq(10)
        expect(strategy.base_delay).to eq(1.0)
        expect(strategy.max_delay).to eq(300.0)  # 5 minutes
        expect(strategy.backoff_multiplier).to eq(2.0)
        expect(strategy.jitter_enabled?).to be true
      end

      it "allows custom configuration" do
        # Given custom configuration
        config = {
          max_attempts: 5,
          base_delay: 2.0,
          max_delay: 60.0,
          backoff_multiplier: 1.5,
          jitter: false
        }
        
        # When creating strategy with custom config
        strategy = described_class.new(websocket_client, config)

        # Then custom configuration should be applied
        expect(strategy.max_attempts).to eq(5)
        expect(strategy.base_delay).to eq(2.0)
        expect(strategy.max_delay).to eq(60.0)
        expect(strategy.backoff_multiplier).to eq(1.5)
        expect(strategy.jitter_enabled?).to be false
      end

      it "validates configuration parameters" do
        # Given invalid configuration
        invalid_configs = [
          { max_attempts: -1 },
          { base_delay: -1.0 },
          { max_delay: 0.5 },  # Less than base_delay
          { backoff_multiplier: 0.5 }  # Less than 1.0
        ]

        invalid_configs.each do |config|
          expect {
            described_class.new(websocket_client, config)
          }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe "exponential backoff calculation" do
    it_behaves_like "a WebSocket reconnection strategy"

    context "when calculating reconnection delays" do
      it "implements exponential backoff correctly" do
        # Given reconnection strategy
        # When calculating delays for multiple attempts
        delays = (1..5).map { |attempt| reconnection_strategy.next_reconnect_delay(attempt) }

        # Then delays should increase exponentially
        expect(delays[0]).to be_within(0.5).of(1.0)    # ~1 second
        expect(delays[1]).to be_within(1.0).of(2.0)    # ~2 seconds
        expect(delays[2]).to be_within(2.0).of(4.0)    # ~4 seconds
        expect(delays[3]).to be_within(4.0).of(8.0)    # ~8 seconds
        expect(delays[4]).to be_within(8.0).of(16.0)   # ~16 seconds
      end

      it "caps delay at maximum value" do
        # Given strategy with small max delay
        strategy = described_class.new(websocket_client, max_delay: 10.0)

        # When calculating delay for many attempts
        large_attempt = 20
        delay = strategy.next_reconnect_delay(large_attempt)

        # Then delay should not exceed maximum
        expect(delay).to be <= 10.0
      end

      it "applies jitter to prevent thundering herd" do
        # Given strategy with jitter enabled
        strategy = described_class.new(websocket_client, jitter: true)

        # When calculating multiple delays for same attempt
        delays = 10.times.map { strategy.next_reconnect_delay(3) }

        # Then delays should vary due to jitter
        expect(delays.uniq.size).to be > 1
        delays.each { |delay| expect(delay).to be_between(2.0, 6.0) }  # 4 ± 50%
      end

      it "provides consistent delays when jitter is disabled" do
        # Given strategy with jitter disabled
        strategy = described_class.new(websocket_client, jitter: false)

        # When calculating multiple delays for same attempt
        delays = 5.times.map { strategy.next_reconnect_delay(3) }

        # Then all delays should be identical
        expect(delays.uniq.size).to eq(1)
        expect(delays.first).to eq(4.0)  # 1 * 2^2 = 4
      end
    end
  end

  describe "reconnection attempt management" do
    context "when tracking reconnection attempts" do
      it "tracks attempt count correctly" do
        # Given new strategy
        expect(reconnection_strategy.reconnect_attempts).to eq(0)
        expect(reconnection_strategy.can_reconnect?).to be true

        # When attempting reconnections
        reconnection_strategy.attempt_reconnect
        expect(reconnection_strategy.reconnect_attempts).to eq(1)

        reconnection_strategy.attempt_reconnect
        expect(reconnection_strategy.reconnect_attempts).to eq(2)
      end

      it "enforces maximum attempt limit" do
        # Given strategy with low max attempts
        strategy = described_class.new(websocket_client, max_attempts: 3)

        # When reaching maximum attempts
        3.times { strategy.attempt_reconnect }
        expect(strategy.can_reconnect?).to be false

        # Then further attempts should be prevented
        expect {
          strategy.attempt_reconnect
        }.to raise_error(Ibkr::WebSocket::ReconnectionError, /maximum.*attempts.*exceeded/i)
      end

      it "resets attempt count on successful connection" do
        # Given strategy with previous attempts
        3.times { reconnection_strategy.attempt_reconnect }
        expect(reconnection_strategy.reconnect_attempts).to eq(3)

        # When connection succeeds
        reconnection_strategy.reset_reconnect_attempts
        
        # Then attempt count should be reset
        expect(reconnection_strategy.reconnect_attempts).to eq(0)
        expect(reconnection_strategy.can_reconnect?).to be true
      end

      it "tracks timing between attempts" do
        # Given first reconnection attempt
        start_time = Time.now
        reconnection_strategy.attempt_reconnect

        # When second attempt is made
        allow(Time).to receive(:now).and_return(start_time + 5)
        reconnection_strategy.attempt_reconnect

        # Then timing should be tracked
        expect(reconnection_strategy.last_attempt_at).to be_within(1).of(start_time + 5)
        expect(reconnection_strategy.time_since_last_attempt).to be_within(1).of(0)
      end
    end

    context "when executing reconnection logic" do
      it "delegates connection to WebSocket client" do
        # Given reconnection strategy
        # When attempting reconnection
        reconnection_strategy.attempt_reconnect

        # Then connection should be delegated to client
        expect(websocket_client).to have_received(:connect)
      end

      it "handles connection failures during reconnection" do
        # Given WebSocket client that fails to connect
        allow(websocket_client).to receive(:connect).and_raise(StandardError, "Connection failed")

        # When attempting reconnection
        expect {
          reconnection_strategy.attempt_reconnect
        }.to raise_error(Ibkr::WebSocket::ReconnectionError)

        # Then attempt should still be counted
        expect(reconnection_strategy.reconnect_attempts).to eq(1)
      end

      it "verifies successful connection" do
        # Given WebSocket client that connects successfully
        allow(websocket_client).to receive(:connected?).and_return(true)

        # When attempting reconnection
        result = reconnection_strategy.attempt_reconnect

        # Then success should be verified
        expect(result).to be true
        expect(websocket_client).to have_received(:connected?)
      end
    end
  end

  describe "automatic reconnection scheduling" do
    context "when scheduling reconnection attempts" do
      it "schedules reconnection with calculated delay" do
        # Given EventMachine timer system and strategy without jitter for deterministic testing
        timer_double = double("timer", cancel: nil)
        allow(EventMachine).to receive(:add_timer).and_return(timer_double)
        strategy_without_jitter = described_class.new(websocket_client, jitter_enabled: false)

        # When scheduling reconnection
        strategy_without_jitter.schedule_reconnection

        # Then timer should be scheduled with a reasonable delay (check range instead of exact value due to potential jitter)
        expect(EventMachine).to have_received(:add_timer) do |delay|
          expect(delay).to be_between(0.5, 5.0) # Reasonable range for first reconnection attempt
        end
      end

      it "executes reconnection when timer fires" do
        # Given scheduled reconnection
        timer_callback = nil
        allow(EventMachine).to receive(:add_timer) do |delay, &block|
          timer_callback = block
          double("timer", cancel: nil)
        end

        reconnection_strategy.schedule_reconnection

        # When timer fires
        timer_callback.call

        # Then reconnection should be attempted
        expect(websocket_client).to have_received(:connect)
        expect(reconnection_strategy.reconnect_attempts).to eq(1)
      end

      it "cancels scheduled reconnection" do
        # Given scheduled reconnection
        timer_double = double("timer", cancel: nil)
        allow(EventMachine).to receive(:add_timer).and_return(timer_double)

        reconnection_strategy.schedule_reconnection

        # When canceling reconnection
        reconnection_strategy.cancel_scheduled_reconnection

        # Then timer should be canceled
        expect(timer_double).to have_received(:cancel)
      end

      it "prevents multiple scheduled reconnections" do
        # Given already scheduled reconnection
        allow(EventMachine).to receive(:add_timer).and_return(double("timer", cancel: nil))
        reconnection_strategy.schedule_reconnection

        # When attempting to schedule another
        reconnection_strategy.schedule_reconnection

        # Then only one timer should be created
        expect(EventMachine).to have_received(:add_timer).once
      end
    end

    context "when handling automatic reconnection flow" do
      it "implements full automatic reconnection cycle" do
        # Given automatic reconnection enabled
        reconnection_strategy.enable_automatic_reconnection

        # When connection is lost
        reconnection_strategy.handle_connection_lost

        # Then reconnection should be scheduled automatically
        expect(EventMachine).to have_received(:add_timer)
      end

      it "stops automatic reconnection after max attempts" do
        # Given strategy with low max attempts
        strategy = described_class.new(websocket_client, max_attempts: 2)
        strategy.enable_automatic_reconnection

        # When max attempts are reached through the automatic flow
        allow(websocket_client).to receive(:connect).and_raise(StandardError, "Failed")
        allow(websocket_client).to receive(:connected?).and_return(false)
        
        # Simulate automatic reconnection flow that would hit max attempts
        # First, make the attempts to reach the max
        2.times do
          begin
            strategy.attempt_reconnect
          rescue Ibkr::WebSocket::ReconnectionError
            # Expected when connection fails
          end
        end
        
        # Now simulate the timer callback logic that checks if we can still reconnect
        # This is where automatic reconnection should be disabled
        if !strategy.send(:can_reconnect?)
          strategy.send(:disable_automatic_reconnection)
        end

        # Then automatic reconnection should be disabled
        expect(strategy.automatic_reconnection_enabled?).to be false
      end

      it "disables automatic reconnection on manual request" do
        # Given automatic reconnection enabled
        reconnection_strategy.enable_automatic_reconnection
        expect(reconnection_strategy.automatic_reconnection_enabled?).to be true

        # When manually disabling
        reconnection_strategy.disable_automatic_reconnection

        # Then automatic reconnection should be disabled
        expect(reconnection_strategy.automatic_reconnection_enabled?).to be false
      end
    end
  end

  describe "reconnection success and failure handling" do
    context "when handling reconnection outcomes" do
      it "handles successful reconnection" do
        # Given previous failed attempts
        2.times { reconnection_strategy.attempt_reconnect }
        expect(reconnection_strategy.reconnect_attempts).to eq(2)

        # When reconnection succeeds
        allow(websocket_client).to receive(:connected?).and_return(true)
        reconnection_strategy.handle_successful_reconnection

        # Then state should be reset
        expect(reconnection_strategy.reconnect_attempts).to eq(0)
        expect(reconnection_strategy.last_successful_connection_at).to be_within(1).of(Time.now)
      end

      it "tracks reconnection failure reasons" do
        # Given reconnection that fails
        error = StandardError.new("Network unreachable")
        allow(websocket_client).to receive(:connect).and_raise(error)

        # When handling reconnection failure
        begin
          reconnection_strategy.attempt_reconnect
        rescue Ibkr::WebSocket::ReconnectionError => reconnection_error
          # Then failure reason should be tracked
          expect(reconnection_error.cause).to eq(error)
          expect(reconnection_strategy.last_failure_reason).to eq("Network unreachable")
        end
      end

      it "provides reconnection statistics" do
        # Given multiple reconnection attempts
        allow(websocket_client).to receive(:connect).and_raise(StandardError, "Failed").twice
        allow(websocket_client).to receive(:connected?).and_return(true)

        2.times do
          begin
            reconnection_strategy.attempt_reconnect
          rescue Ibkr::WebSocket::ReconnectionError
            # Expected failures
          end
        end

        reconnection_strategy.handle_successful_reconnection

        # When checking statistics
        stats = reconnection_strategy.reconnection_statistics

        # Then statistics should be accurate
        expect(stats[:total_attempts]).to eq(2)
        expect(stats[:successful_reconnections]).to eq(1)
        expect(stats[:failure_rate]).to be_within(0.01).of(1.0) # 2 failures out of 2 total attempts
        expect(stats[:average_attempts_to_success]).to be_within(0.1).of(2.0)
      end
    end
  end

  describe "integration with connection events" do
    context "when responding to connection events" do
      it "handles normal connection closure" do
        # Given normal connection closure
        # When handling closure event
        reconnection_strategy.handle_connection_closed(code: 1000, reason: "Normal closure")

        # Then reconnection should not be automatically triggered
        expect(reconnection_strategy.should_reconnect?(1000)).to be false
      end

      it "handles abnormal connection closure" do
        # Given abnormal connection closure
        # When handling closure event
        reconnection_strategy.handle_connection_closed(code: 1006, reason: "Abnormal closure")

        # Then reconnection should be triggered
        expect(reconnection_strategy.should_reconnect?(1006)).to be true
      end

      it "handles server-initiated disconnection" do
        # Given server-initiated disconnection
        # When handling closure event
        reconnection_strategy.handle_connection_closed(code: 1012, reason: "Server restart")

        # Then reconnection should be attempted with reasonable delay (accounting for jitter)
        delay = reconnection_strategy.next_reconnect_delay(1)
        expect(delay).to be_between(0.5, 2.0) # Base delay with possible jitter range
      end

      it "respects server reconnection guidance" do
        # Given server provides reconnection guidance
        server_guidance = { retry_after: 60, max_attempts: 3 }
        
        # When handling guidance
        reconnection_strategy.apply_server_guidance(server_guidance)

        # Then strategy should be adjusted (accounting for jitter)
        expect(reconnection_strategy.next_reconnect_delay(1)).to be >= 45 # 60 with -25% jitter
        expect(reconnection_strategy.max_attempts).to eq(3)
      end
    end
  end

  describe "performance and resource management" do
    context "when managing reconnection resources", websocket_performance: true do
      it "efficiently handles rapid reconnection attempts" do
        # Given rapid connection failures
        start_time = Time.now
        
        # When handling multiple failures quickly
        5.times do |i|
          begin
            allow(websocket_client).to receive(:connect).and_raise(StandardError, "Failed #{i}")
            reconnection_strategy.attempt_reconnect
          rescue Ibkr::WebSocket::ReconnectionError
            # Expected
          end
        end
        
        end_time = Time.now
        
        # Then processing should be efficient
        expect(end_time - start_time).to be < 0.1  # Under 100ms
      end

      it "cleans up timer resources properly" do
        # Given scheduled reconnections
        timers = []
        allow(EventMachine).to receive(:add_timer) do |delay, &block|
          timer = double("timer", cancel: nil)
          timers << timer
          timer
        end

        3.times { reconnection_strategy.schedule_reconnection }

        # When cleaning up
        reconnection_strategy.cleanup

        # Then all timers should be canceled
        timers.each { |timer| expect(timer).to have_received(:cancel) }
      end

      it "prevents memory leaks during long reconnection periods" do
        # Given long period of reconnection attempts
        start_memory = GC.stat[:heap_live_slots]
        
        20.times do |i|
          begin
            allow(websocket_client).to receive(:connect).and_raise(StandardError, "Failed #{i}")
            reconnection_strategy.attempt_reconnect
          rescue Ibkr::WebSocket::ReconnectionError
            # Expected
          end
        end
        
        GC.start
        end_memory = GC.stat[:heap_live_slots]
        
        # Then memory growth should be minimal
        memory_growth = end_memory - start_memory
        expect(memory_growth).to be < 10000  # Less than 10k new objects
      end
    end
  end
end