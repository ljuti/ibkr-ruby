# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::WebSocket::SubscriptionManager, websocket: true do
  include_context "with WebSocket test environment"
  include_context "with WebSocket subscriptions"

  let(:websocket_client) { double("websocket_client", send_message: true, authenticated?: true, emit: true, account_id: "DU123456") }
  let(:subscription_manager) { described_class.new(websocket_client) }
  let(:subscription_request) { market_data_subscription }

  subject { subscription_manager }

  describe "initialization" do
    context "when creating subscription manager" do
      it "initializes with empty subscription state" do
        # Given new subscription manager
        manager = described_class.new(websocket_client)

        # Then initial state should be empty
        expect(manager.subscriptions).to be_empty
        expect(manager.subscription_count).to eq(0)
        expect(manager.active_channels).to be_empty
      end

      it "validates WebSocket client dependency" do
        # Given missing WebSocket client
        # When creating manager without client
        # Then it should raise error
        expect {
          described_class.new(nil)
        }.to raise_error(ArgumentError, /websocket_client is required/)
      end
    end
  end

  describe "subscription lifecycle management" do
    it_behaves_like "a WebSocket subscription manager"

    context "when creating subscriptions" do
      it "generates unique subscription IDs" do
        # Given subscription manager
        # When creating multiple subscriptions
        id1 = subscription_manager.subscribe(market_data_subscription)
        id2 = subscription_manager.subscribe(portfolio_subscription)
        id3 = subscription_manager.subscribe(order_subscription)

        # Then each subscription should have unique ID
        expect([id1, id2, id3].uniq.size).to eq(3)
        expect(id1).to match(/^sub_[a-f0-9]{8,}$/)
      end

      it "tracks subscription metadata" do
        # Given subscription request
        # When creating subscription
        subscription_id = subscription_manager.subscribe(market_data_subscription)

        # Then metadata should be tracked
        subscription = subscription_manager.get_subscription(subscription_id)
        expect(subscription[:channel]).to eq("market_data")
        expect(subscription[:symbols]).to eq(["AAPL", "GOOGL"])
        expect(subscription[:fields]).to eq(["price", "volume", "bid", "ask"])
        expect(subscription[:created_at]).to be_a(Time)
        expect(subscription[:status]).to eq(:pending)
      end

      it "sends subscription message to WebSocket" do
        # Given authenticated WebSocket client
        # When creating subscription
        subscription_id = subscription_manager.subscribe(market_data_subscription)

        # Then subscription message should be sent
        expect(websocket_client).to have_received(:send_message) do |message|
          expect(message[:type]).to eq("subscribe")
          expect(message[:subscription_id]).to eq(subscription_id)
          expect(message[:channel]).to eq("market_data")
          expect(message[:symbols]).to eq(["AAPL", "GOOGL"])
        end
      end

      it "prevents duplicate subscriptions for same parameters" do
        # Given existing subscription
        id1 = subscription_manager.subscribe(market_data_subscription)

        # When attempting to create identical subscription
        id2 = subscription_manager.subscribe(market_data_subscription)

        # Then same subscription ID should be returned
        expect(id1).to eq(id2)
        expect(subscription_manager.subscription_count).to eq(1)
      end
    end

    context "when managing subscription status" do
      it "updates subscription status on server response" do
        # Given pending subscription
        subscription_id = subscription_manager.subscribe(market_data_subscription)
        expect(subscription_manager.get_subscription(subscription_id)[:status]).to eq(:pending)

        # When server confirms subscription
        subscription_manager.handle_subscription_response(
          subscription_id: subscription_id,
          status: "success"
        )

        # Then status should be updated
        expect(subscription_manager.get_subscription(subscription_id)[:status]).to eq(:active)
        expect(subscription_manager.active_subscriptions).to include(subscription_id)
      end

      it "handles subscription errors" do
        # Given pending subscription
        subscription_id = subscription_manager.subscribe(market_data_subscription)

        # When server returns error
        subscription_manager.handle_subscription_response(
          subscription_id: subscription_id,
          status: "error",
          error: "invalid_symbol",
          message: "Symbol INVALID not found"
        )

        # Then error should be tracked
        subscription = subscription_manager.get_subscription(subscription_id)
        expect(subscription[:status]).to eq(:error)
        expect(subscription[:error]).to eq("invalid_symbol")
        expect(subscription[:error_message]).to eq("Symbol INVALID not found")
      end

      it "tracks subscription confirmation timing" do
        # Given subscription request
        subscription_id = subscription_manager.subscribe(market_data_subscription)
        start_time = Time.now

        # When confirmation arrives
        allow(Time).to receive(:now).and_return(start_time + 0.1)
        subscription_manager.handle_subscription_response(
          subscription_id: subscription_id,
          status: "success"
        )

        # Then timing should be recorded
        subscription = subscription_manager.get_subscription(subscription_id)
        expect(subscription[:confirmed_at]).to be_within(0.01).of(start_time + 0.1)
        expect(subscription[:confirmation_latency]).to be_within(0.01).of(0.1)
      end
    end

    context "when removing subscriptions" do
      it "unsubscribes from active subscriptions" do
        # Given active subscription
        subscription_id = subscription_manager.subscribe(market_data_subscription)
        subscription_manager.handle_subscription_response(
          subscription_id: subscription_id,
          status: "success"
        )
        expect(subscription_manager.active_subscriptions).to include(subscription_id)

        # When unsubscribing
        subscription_manager.unsubscribe(subscription_id)

        # Then subscription should be removed
        expect(subscription_manager.active_subscriptions).not_to include(subscription_id)
        expect(subscription_manager.get_subscription(subscription_id)).to be_nil

        # And unsubscribe message should be sent (2 calls total: subscribe + unsubscribe)
        expect(websocket_client).to have_received(:send_message).twice

        # Check the last call was an unsubscribe message
        expect(websocket_client).to have_received(:send_message).with(
          hash_including(
            type: "unsubscribe",
            subscription_id: subscription_id
          )
        )
      end

      it "handles unsubscribe from non-existent subscription gracefully" do
        # Given non-existent subscription ID
        fake_id = "sub_nonexistent"

        # When attempting to unsubscribe
        result = subscription_manager.unsubscribe(fake_id)

        # Then operation should complete without error
        expect(result).to be false
        expect(subscription_manager.subscription_count).to eq(0)
      end

      it "cleans up all subscriptions" do
        # Given multiple active subscriptions
        3.times do |i|
          subscription_id = subscription_manager.subscribe(
            channel: "market_data",
            symbols: ["STOCK#{i}"]
          )
          subscription_manager.handle_subscription_response(
            subscription_id: subscription_id,
            status: "success"
          )
        end
        expect(subscription_manager.subscription_count).to eq(3)

        # When cleaning up all subscriptions
        subscription_manager.unsubscribe_all

        # Then all subscriptions should be removed
        expect(subscription_manager.subscription_count).to eq(0)
        expect(subscription_manager.active_subscriptions).to be_empty
      end
    end
  end

  describe "subscription limits and rate limiting" do
    context "when enforcing subscription limits" do
      it "enforces overall subscription limit to maintain system stability" do
        # Given a trading environment with conservative limits
        manager = described_class.new(websocket_client)
        manager.configure_for_testing(limits: {total: 2})

        # When trader creates subscriptions up to their limit
        manager.subscribe(channel: "market_data", symbols: ["AAPL"])
        manager.subscribe(channel: "market_data", symbols: ["GOOGL"])

        # Then additional subscriptions are rejected with clear guidance
        expect {
          manager.subscribe(channel: "market_data", symbols: ["MSFT"])
        }.to raise_error(Ibkr::WebSocket::SubscriptionError, /limit exceeded/i)
      end

      it "applies channel-specific limits for specialized data streams" do
        # Given a system with conservative portfolio subscription limits
        manager = described_class.new(websocket_client)
        manager.configure_for_testing(limits: {portfolio: 2})

        # When trader creates portfolio subscriptions up to limit
        2.times { |i| manager.subscribe(channel: "portfolio", account_id: "DU000#{i}") }

        # Then additional portfolio subscriptions are prevented
        expect {
          manager.subscribe(channel: "portfolio", account_id: "DU_OVERFLOW")
        }.to raise_error(Ibkr::WebSocket::SubscriptionError, /limit exceeded.*portfolio/i)
      end

      it "throttles rapid subscription requests to prevent system overload" do
        # Given a system configured for moderate request rates
        manager = described_class.new(websocket_client)
        manager.configure_for_testing(rate_limit: 10)

        # When trader makes rapid subscription requests
        start_time = Time.now
        allow(Time).to receive(:now).and_return(start_time)

        10.times { |i| manager.subscribe(channel: "market_data", symbols: ["STOCK#{i}"]) }

        # Then subsequent requests are rate limited
        expect {
          manager.subscribe(channel: "market_data", symbols: ["OVER_LIMIT"])
        }.to raise_error(Ibkr::WebSocket::SubscriptionError, /rate limit exceeded/i)
      end
    end

    context "when handling rate limit responses" do
      it "respects server-side rate limiting" do
        # Given subscription that hits server rate limit
        subscription_id = subscription_manager.subscribe(market_data_subscription)

        # When server returns rate limit error
        subscription_manager.handle_subscription_response(
          subscription_id: subscription_id,
          status: "error",
          error: "rate_limit_exceeded",
          retry_after: 60
        )

        # Then rate limit should be tracked
        expect(subscription_manager.rate_limited?).to be true
        expect(subscription_manager.rate_limit_retry_after).to eq(60)
        expect(subscription_manager.rate_limit_resets_at).to be_within(5).of(Time.now + 60)
      end

      it "automatically retries after rate limit expires" do
        # Given rate limited manager
        subscription_id = subscription_manager.subscribe(market_data_subscription)
        subscription_manager.handle_subscription_response(
          subscription_id: subscription_id,
          status: "error",
          error: "rate_limit_exceeded",
          retry_after: 1
        )

        # When rate limit period expires
        allow(Time).to receive(:now).and_return(Time.now + 2)

        # Then new subscriptions should be allowed
        expect(subscription_manager.rate_limited?).to be false
        expect {
          subscription_manager.subscribe(portfolio_subscription)
        }.not_to raise_error
      end
    end
  end

  describe "subscription filtering and grouping" do
    context "when managing subscription collections" do
      it "filters subscriptions by channel" do
        # Given subscriptions for different channels
        market_id = subscription_manager.subscribe(market_data_subscription)
        portfolio_id = subscription_manager.subscribe(portfolio_subscription)
        order_id = subscription_manager.subscribe(order_subscription)

        # When filtering by channel
        market_subs = subscription_manager.subscriptions_for_channel("market_data")
        portfolio_subs = subscription_manager.subscriptions_for_channel("portfolio")

        # Then filtering should work correctly
        expect(market_subs).to include(market_id)
        expect(market_subs).not_to include(portfolio_id, order_id)
        expect(portfolio_subs).to include(portfolio_id)
        expect(portfolio_subs).not_to include(market_id, order_id)
      end

      it "groups subscriptions by symbol" do
        # Given subscriptions for different symbols
        aapl_id = subscription_manager.subscribe(
          channel: "market_data",
          symbols: ["AAPL"],
          fields: ["price"]
        )
        googl_id = subscription_manager.subscribe(
          channel: "market_data",
          symbols: ["GOOGL"],
          fields: ["price"]
        )
        multi_id = subscription_manager.subscribe(
          channel: "market_data",
          symbols: ["AAPL", "MSFT"],
          fields: ["volume"]
        )

        # When grouping by symbol
        aapl_subs = subscription_manager.subscriptions_for_symbol("AAPL")
        googl_subs = subscription_manager.subscriptions_for_symbol("GOOGL")

        # Then grouping should include relevant subscriptions
        expect(aapl_subs).to include(aapl_id, multi_id)
        expect(aapl_subs).not_to include(googl_id)
        expect(googl_subs).to include(googl_id)
        expect(googl_subs).not_to include(aapl_id, multi_id)
      end

      it "tracks subscription statistics" do
        # Given various subscriptions
        5.times { |i| subscription_manager.subscribe(channel: "market_data", symbols: ["STOCK#{i}"]) }
        3.times { |i| subscription_manager.subscribe(channel: "portfolio", account_id: "DU#{i}") }
        2.times { |i| subscription_manager.subscribe(channel: "orders", account_id: "DU#{i}") }

        # When checking statistics
        stats = subscription_manager.subscription_statistics

        # Then statistics should be accurate
        expect(stats[:total]).to eq(10)
        expect(stats[:by_channel]["market_data"]).to eq(5)
        expect(stats[:by_channel]["portfolio"]).to eq(3)
        expect(stats[:by_channel]["orders"]).to eq(2)
        expect(stats[:pending]).to eq(10) # All pending since no confirmations
        expect(stats[:active]).to eq(0)
      end
    end
  end

  describe "subscription persistence and recovery" do
    context "when handling connection recovery" do
      it "provides subscription state for reconnection" do
        # Given active subscriptions before disconnect
        market_id = subscription_manager.subscribe(market_data_subscription)
        portfolio_id = subscription_manager.subscribe(portfolio_subscription)

        subscription_manager.handle_subscription_response(subscription_id: market_id, status: "success")
        subscription_manager.handle_subscription_response(subscription_id: portfolio_id, status: "success")

        # When preparing for reconnection
        recovery_state = subscription_manager.get_recovery_state

        # Then recovery state should include active subscriptions
        expect(recovery_state[:subscriptions]).to be_an(Array)
        expect(recovery_state[:subscriptions].size).to eq(2)
        expect(recovery_state[:subscriptions]).to all(include(:channel, :parameters, :subscription_id))
      end

      it "restores subscriptions after reconnection" do
        # Given recovery state from previous session
        recovery_state = {
          subscriptions: [
            {
              subscription_id: "sub_123",
              channel: "market_data",
              parameters: {symbols: ["AAPL"], fields: ["price"]}
            },
            {
              subscription_id: "sub_456",
              channel: "portfolio",
              parameters: {account_id: "DU123456"}
            }
          ]
        }

        # When restoring from recovery state
        subscription_manager.restore_from_recovery_state(recovery_state)

        # Then subscriptions should be recreated
        expect(subscription_manager.subscription_count).to eq(2)
        expect(subscription_manager.subscriptions).to include("sub_123", "sub_456")

        # And subscription messages should be sent
        expect(websocket_client).to have_received(:send_message).twice
      end

      it "handles partial restoration failures gracefully" do
        # Given recovery state with some invalid subscriptions
        recovery_state = {
          subscriptions: [
            {subscription_id: "sub_valid", channel: "market_data", parameters: {symbols: ["AAPL"]}},
            {subscription_id: "sub_invalid", channel: "invalid_channel", parameters: {}}
          ]
        }

        # When restoring subscriptions
        result = subscription_manager.restore_from_recovery_state(recovery_state)

        # Then valid subscriptions should be restored, invalid ones skipped
        expect(result[:restored]).to eq(1)
        expect(result[:failed]).to eq(1)
        expect(subscription_manager.subscription_count).to eq(1)
        expect(subscription_manager.subscriptions).to include("sub_valid")
      end
    end
  end

  describe "performance and memory management" do
    context "when handling high subscription volumes", websocket_performance: true do
      it "efficiently manages large numbers of subscriptions" do
        # Given a system configured for high-volume trading operations
        manager = described_class.new(websocket_client)
        manager.configure_for_testing(
          limits: {total: 2000, market_data: 2000},
          rate_limit: 2000  # No rate limiting for performance test
        )
        subscription_count = 1000

        start_time = Time.now
        subscription_ids = []

        subscription_count.times do |i|
          id = manager.subscribe(
            channel: "market_data",
            symbols: ["STOCK#{i % 100}"],  # Reuse symbols to test deduplication
            fields: ["price"]
          )
          subscription_ids << id
        end

        end_time = Time.now

        # Then operations should be efficient
        expect(end_time - start_time).to be < 1.0  # Under 1 second
        expect(manager.subscription_count).to be <= subscription_count
      end

      it "cleans up subscription memory efficiently" do
        # Given a system with many active trading subscriptions
        manager = described_class.new(websocket_client)
        manager.configure_for_testing(
          limits: {total: 200, market_data: 200},
          rate_limit: 200  # No rate limiting for performance test
        )

        100.times do |i|
          id = manager.subscribe(channel: "market_data", symbols: ["STOCK#{i}"])
          manager.handle_subscription_response(subscription_id: id, status: "success")
        end

        start_memory = GC.stat[:heap_live_slots]

        # When cleaning up all subscriptions
        manager.unsubscribe_all

        GC.start
        end_memory = GC.stat[:heap_live_slots]

        # Then memory should be efficiently reclaimed
        expect(manager.subscription_count).to eq(0)
        expect(end_memory).to be <= start_memory
      end
    end
  end
end
