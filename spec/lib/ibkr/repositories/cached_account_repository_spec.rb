# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Repositories::CachedAccountRepository do
  let(:mock_client) { double("client") }
  let(:mock_underlying_repository) { double("underlying_repository") }

  let(:account_id) { "DU123456" }
  let(:contract_id) { 123456 }

  let(:sample_summary) do
    {
      "accountId" => account_id,
      "totalCashValue" => "100000.00",
      "netLiquidation" => "120000.00"
    }
  end

  let(:sample_metadata) do
    {
      "accountId" => account_id,
      "accountType" => "DEMO",
      "tradingPermissions" => ["STOCKS", "OPTIONS"]
    }
  end

  let(:sample_positions) do
    {
      "results" => [
        {
          "contractId" => 123,
          "position" => "100",
          "marketPrice" => "150.25"
        }
      ]
    }
  end

  let(:sample_transactions) do
    [
      {
        "transactionId" => "T001",
        "date" => "2023-12-01",
        "amount" => "1000.00"
      }
    ]
  end

  let(:sample_accounts) { ["DU123456", "DU789012"] }

  describe "initialization" do
    context "when initialized with default settings" do
      it "creates a working repository that can fetch data" do
        expect(Ibkr::Repositories::ApiAccountRepository).to receive(:new).with(mock_client).and_return(mock_underlying_repository)

        repository = described_class.new(mock_client)

        # Verify it works by testing a simple operation
        expect(mock_underlying_repository).to receive(:discover_accounts).and_return(sample_accounts)
        result = repository.discover_accounts
        expect(result).to eq(sample_accounts)
      end
    end

    context "when initialized with custom settings" do
      let(:custom_ttl) { {summary: 60, positions: 5} }
      let(:repository) do
        described_class.new(
          mock_client,
          underlying_repository: mock_underlying_repository,
          cache_ttl: custom_ttl
        )
      end

      it "uses provided underlying repository for operations" do
        expect(mock_underlying_repository).to receive(:find_summary).with(account_id).and_return(sample_summary)

        result = repository.find_summary(account_id)
        expect(result).to eq(sample_summary)
      end

      it "respects custom TTL settings for caching behavior" do
        # Test that custom TTL affects caching by making the same call twice
        expect(mock_underlying_repository).to receive(:find_summary).once.and_return(sample_summary)

        # First call should hit the underlying repository
        result1 = repository.find_summary(account_id)

        # Second call should use cache (verify by underlying repository not being called again)
        result2 = repository.find_summary(account_id)

        expect(result1).to eq(sample_summary)
        expect(result2).to eq(sample_summary)
      end
    end
  end

  describe "#find_summary" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    context "when data is not cached" do
      it "fetches from underlying repository and returns correct result" do
        expect(mock_underlying_repository).to receive(:find_summary)
          .with(account_id)
          .and_return(sample_summary)

        result = repository.find_summary(account_id)

        expect(result).to eq(sample_summary)
      end
    end

    context "when data is cached and valid" do
      it "returns cached data without calling underlying repository on repeated calls" do
        expect(mock_underlying_repository).to receive(:find_summary)
          .once
          .and_return(sample_summary)

        # First call fetches from underlying repository
        result1 = repository.find_summary(account_id)

        # Second call should use cache (verify by mock expectation)
        result2 = repository.find_summary(account_id)

        expect(result1).to eq(sample_summary)
        expect(result2).to eq(sample_summary)
      end
    end

    context "when cached data expires" do
      it "refetches data when cache TTL is exceeded" do
        # Use a very short TTL for this test
        short_ttl_repository = described_class.new(
          mock_client,
          underlying_repository: mock_underlying_repository,
          cache_ttl: {summary: 0.01} # 10ms TTL
        )

        updated_summary = sample_summary.merge("totalCashValue" => "110000.00")

        expect(mock_underlying_repository).to receive(:find_summary)
          .twice
          .and_return(sample_summary, updated_summary)

        # First call
        result1 = short_ttl_repository.find_summary(account_id)

        # Wait for cache to expire
        sleep(0.02)

        # Second call should fetch fresh data
        result2 = short_ttl_repository.find_summary(account_id)

        expect(result1).to eq(sample_summary)
        expect(result2).to eq(updated_summary)
      end
    end
  end

  describe "#find_metadata" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    context "when caching metadata with longer TTL" do
      it "caches metadata for repeated access" do
        expect(mock_underlying_repository).to receive(:find_metadata)
          .once
          .and_return(sample_metadata)

        # First call fetches from underlying repository
        result1 = repository.find_metadata(account_id)

        # Second call should use cache (metadata has longer TTL)
        result2 = repository.find_metadata(account_id)

        expect(result1).to eq(sample_metadata)
        expect(result2).to eq(sample_metadata)
      end
    end

    context "when metadata has different caching behavior than summary" do
      it "respects longer TTL for metadata compared to summary" do
        # Create repository with very short summary TTL but normal metadata TTL
        repository_with_short_summary_ttl = described_class.new(
          mock_client,
          underlying_repository: mock_underlying_repository,
          cache_ttl: {summary: 0.01, metadata: 30} # 10ms vs 30s
        )

        expect(mock_underlying_repository).to receive(:find_metadata).once.and_return(sample_metadata)
        expect(mock_underlying_repository).to receive(:find_summary).twice.and_return(sample_summary)

        # Both calls initially
        repository_with_short_summary_ttl.find_metadata(account_id)
        repository_with_short_summary_ttl.find_summary(account_id)

        sleep(0.02) # Wait for summary cache to expire

        # Metadata should still be cached, summary should refetch
        repository_with_short_summary_ttl.find_metadata(account_id)
        repository_with_short_summary_ttl.find_summary(account_id)
      end
    end
  end

  describe "#find_positions" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end
    let(:options) { {page: 1, sort: "name"} }

    context "when caching positions with different options" do
      it "handles different query options separately" do
        expect(mock_underlying_repository).to receive(:find_positions)
          .with(account_id, options)
          .and_return(sample_positions)

        result = repository.find_positions(account_id, options)

        expect(result).to eq(sample_positions)
      end
    end

    context "when different options create different cache entries" do
      let(:options1) { {page: 1, sort: "name"} }
      let(:options2) { {page: 2, sort: "name"} }
      let(:positions1) { {"results" => [{"page" => 1}]} }
      let(:positions2) { {"results" => [{"page" => 2}]} }

      it "maintains separate cached results for different option sets" do
        expect(mock_underlying_repository).to receive(:find_positions)
          .with(account_id, options1).once.and_return(positions1)
        expect(mock_underlying_repository).to receive(:find_positions)
          .with(account_id, options2).once.and_return(positions2)

        # First call to each option set
        result1a = repository.find_positions(account_id, options1)
        result2a = repository.find_positions(account_id, options2)

        # Second call to each option set should use cache
        result1b = repository.find_positions(account_id, options1)
        result2b = repository.find_positions(account_id, options2)

        expect(result1a).to eq(positions1)
        expect(result1b).to eq(positions1)
        expect(result2a).to eq(positions2)
        expect(result2b).to eq(positions2)
      end
    end

    context "when positions cache has shorter TTL" do
      it "refreshes positions more frequently than other data types" do
        # Create repository with very short positions TTL
        short_positions_ttl_repository = described_class.new(
          mock_client,
          underlying_repository: mock_underlying_repository,
          cache_ttl: {positions: 0.01, summary: 30} # 10ms vs 30s
        )

        updated_positions = {"results" => [{"contractId" => 123, "position" => "150"}]}

        expect(mock_underlying_repository).to receive(:find_positions)
          .twice
          .and_return(sample_positions, updated_positions)
        expect(mock_underlying_repository).to receive(:find_summary)
          .once
          .and_return(sample_summary)

        # Initial calls
        short_positions_ttl_repository.find_positions(account_id, options)
        short_positions_ttl_repository.find_summary(account_id)

        sleep(0.02) # Wait for positions cache to expire

        # Positions should refetch, summary should remain cached
        result_positions = short_positions_ttl_repository.find_positions(account_id, options)
        result_summary = short_positions_ttl_repository.find_summary(account_id)

        expect(result_positions).to eq(updated_positions)
        expect(result_summary).to eq(sample_summary)
      end
    end
  end

  describe "#find_transactions" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end
    let(:days) { 30 }

    context "when caching transaction history" do
      it "caches transactions with all parameters considered" do
        expect(mock_underlying_repository).to receive(:find_transactions)
          .once
          .with(account_id, contract_id, days)
          .and_return(sample_transactions)

        # First call fetches from underlying repository
        result1 = repository.find_transactions(account_id, contract_id, days)

        # Second call should use cache
        result2 = repository.find_transactions(account_id, contract_id, days)

        expect(result1).to eq(sample_transactions)
        expect(result2).to eq(sample_transactions)
      end
    end

    context "when using default days parameter" do
      it "caches transactions with default parameter correctly" do
        expect(mock_underlying_repository).to receive(:find_transactions)
          .once
          .with(account_id, contract_id, 90)
          .and_return(sample_transactions)

        # Test with default parameter (should cache)
        result1 = repository.find_transactions(account_id, contract_id)
        result2 = repository.find_transactions(account_id, contract_id)

        expect(result1).to eq(sample_transactions)
        expect(result2).to eq(sample_transactions)
      end

      it "treats explicit and default parameters as the same cache entry" do
        expect(mock_underlying_repository).to receive(:find_transactions)
          .once
          .with(account_id, contract_id, 90)
          .and_return(sample_transactions)

        # Call with default parameter
        result1 = repository.find_transactions(account_id, contract_id)

        # Call with explicit parameter (same as default) - should use cache
        result2 = repository.find_transactions(account_id, contract_id, 90)

        expect(result1).to eq(sample_transactions)
        expect(result2).to eq(sample_transactions)
      end
    end
  end

  describe "#discover_accounts" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    context "when discovering accounts" do
      it "fetches and caches account discovery results" do
        expect(mock_underlying_repository).to receive(:discover_accounts)
          .once
          .and_return(sample_accounts)

        # First call fetches from underlying repository
        result1 = repository.discover_accounts

        # Second call should use cache
        result2 = repository.discover_accounts

        expect(result1).to eq(sample_accounts)
        expect(result2).to eq(sample_accounts)
      end
    end

    context "when accounts are cached" do
      it "uses cached accounts for existence checks" do
        expect(mock_underlying_repository).to receive(:discover_accounts)
          .once
          .and_return(sample_accounts)

        # This should trigger discovery and cache the result
        result1 = repository.account_exists?("DU123456")

        # This should use the cached discovery result
        result2 = repository.account_exists?("DU789012")

        # This should also use cached result
        result3 = repository.discover_accounts

        expect(result1).to be true
        expect(result2).to be true
        expect(result3).to eq(sample_accounts)
      end
    end
  end

  describe "#account_exists?" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    context "when checking account existence" do
      before do
        allow(mock_underlying_repository).to receive(:discover_accounts).and_return(sample_accounts)
      end

      it "returns true for existing accounts" do
        result = repository.account_exists?("DU123456")

        expect(result).to be true
      end

      it "returns false for non-existing accounts" do
        result = repository.account_exists?("DU999999")

        expect(result).to be false
      end
    end

    context "when checking multiple accounts" do
      it "leverages cached discovery for efficiency" do
        expect(mock_underlying_repository).to receive(:discover_accounts).once.and_return(sample_accounts)

        # Multiple existence checks should only trigger one discovery call
        result1 = repository.account_exists?("DU123456")
        result2 = repository.account_exists?("DU789012")
        result3 = repository.account_exists?("DU999999")

        expect(result1).to be true
        expect(result2).to be true
        expect(result3).to be false
      end
    end
  end

  describe "cache management" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    describe "#clear_cache" do
      it "clears all cached data and forces fresh fetches" do
        # First populate the cache
        allow(mock_underlying_repository).to receive(:find_summary).and_return(sample_summary, sample_summary.merge("updated" => "true"))

        # Initial call to populate cache
        repository.find_summary(account_id)

        # Clear cache
        repository.clear_cache

        # Next call should fetch fresh data (verify by checking mock is called again)
        result = repository.find_summary(account_id)

        expect(mock_underlying_repository).to have_received(:find_summary).twice
        expect(result["updated"]).to eq("true")
      end
    end

    describe "#clear_cache_for_account" do
      it "clears cache entries only for the specified account" do
        # Set up mock to return different data for different accounts
        summary_123 = sample_summary.merge("accountId" => "DU123456")
        summary_789 = sample_summary.merge("accountId" => "DU789012")

        allow(mock_underlying_repository).to receive(:find_summary)
          .with("DU123456").and_return(summary_123, summary_123.merge("updated" => "true"))
        allow(mock_underlying_repository).to receive(:find_summary)
          .with("DU789012").and_return(summary_789)

        # Populate cache for both accounts
        repository.find_summary("DU123456")
        repository.find_summary("DU789012")

        # Clear cache for one account
        repository.clear_cache_for_account("DU123456")

        # DU123456 should fetch fresh data, DU789012 should use cache
        result_123 = repository.find_summary("DU123456")
        result_789 = repository.find_summary("DU789012")

        expect(result_123["updated"]).to eq("true") # Fresh data
        expect(result_789["updated"]).to be_nil     # Cached data
        expect(mock_underlying_repository).to have_received(:find_summary).with("DU123456").twice
        expect(mock_underlying_repository).to have_received(:find_summary).with("DU789012").once
      end
    end

    describe "#cache_stats" do
      it "returns meaningful cache statistics" do
        # Populate some cache entries
        allow(mock_underlying_repository).to receive(:find_summary).and_return(sample_summary)
        allow(mock_underlying_repository).to receive(:find_positions).and_return(sample_positions)

        repository.find_summary(account_id)
        repository.find_positions(account_id, {})

        stats = repository.cache_stats

        expect(stats).to include(
          total_entries: be_a(Integer),
          cache_hit_ratio: be_a(Numeric),
          oldest_entry: be_a(Time).or(be_nil),
          cache_size_mb: be_a(Numeric)
        )
        expect(stats[:total_entries]).to be >= 2
      end
    end
  end

  describe "TTL behavior for different data types" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    context "when different data types have different update frequencies" do
      it "respects configured TTL differences between data types" do
        # Create repository with very different TTLs to observe behavior
        repository_with_varied_ttl = described_class.new(
          mock_client,
          underlying_repository: mock_underlying_repository,
          cache_ttl: {
            summary: 0.01,     # 10ms - expires quickly
            metadata: 30,      # 30s - longer lived
            positions: 0.02,   # 20ms - expires quickly
            transactions: 30   # 30s - longer lived
          }
        )

        # Set up mocks to track call counts
        expect(mock_underlying_repository).to receive(:find_summary).twice.and_return(sample_summary)
        expect(mock_underlying_repository).to receive(:find_metadata).once.and_return(sample_metadata)
        expect(mock_underlying_repository).to receive(:find_positions).twice.and_return(sample_positions)
        expect(mock_underlying_repository).to receive(:find_transactions).once.and_return(sample_transactions)

        # Initial calls
        repository_with_varied_ttl.find_summary(account_id)
        repository_with_varied_ttl.find_metadata(account_id)
        repository_with_varied_ttl.find_positions(account_id, {})
        repository_with_varied_ttl.find_transactions(account_id, contract_id, 30)

        # Wait for short TTLs to expire
        sleep(0.03)

        # Make calls again - short TTL items should refetch, long TTL should use cache
        repository_with_varied_ttl.find_summary(account_id)      # Should refetch
        repository_with_varied_ttl.find_metadata(account_id)     # Should use cache
        repository_with_varied_ttl.find_positions(account_id, {}) # Should refetch
        repository_with_varied_ttl.find_transactions(account_id, contract_id, 30) # Should use cache
      end
    end
  end

  describe "error handling and edge cases" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    context "when underlying repository raises errors" do
      it "propagates errors without caching failed results" do
        error = Ibkr::ApiError.new("API Error")
        allow(mock_underlying_repository).to receive(:find_summary)
          .and_raise(error)

        # First call should raise error
        expect {
          repository.find_summary(account_id)
        }.to raise_error(Ibkr::ApiError)

        # Reset the mock for second call
        allow(mock_underlying_repository).to receive(:find_summary)
          .and_return(sample_summary)

        # Second call should work normally (no cached error)
        result = repository.find_summary(account_id)
        expect(result).to eq(sample_summary)
      end
    end

    context "when dealing with nil or empty responses" do
      it "caches nil responses and returns them consistently" do
        allow(mock_underlying_repository).to receive(:find_summary)
          .once
          .and_return(nil)

        # First call returns nil and caches it
        result1 = repository.find_summary(account_id)

        # Second call should return cached nil without calling underlying repository
        result2 = repository.find_summary(account_id)

        expect(result1).to be_nil
        expect(result2).to be_nil
        expect(mock_underlying_repository).to have_received(:find_summary).once
      end

      it "caches empty arrays and returns them consistently" do
        empty_transactions = []
        allow(mock_underlying_repository).to receive(:find_transactions)
          .once
          .and_return(empty_transactions)

        # First call returns empty array and caches it
        result1 = repository.find_transactions(account_id, contract_id)

        # Second call should return cached empty array
        result2 = repository.find_transactions(account_id, contract_id)

        expect(result1).to eq([])
        expect(result2).to eq([])
        expect(mock_underlying_repository).to have_received(:find_transactions).once
      end
    end

    context "when handling concurrent access scenarios" do
      it "maintains cache consistency during rapid successive calls" do
        allow(mock_underlying_repository).to receive(:find_summary)
          .once
          .and_return(sample_summary)

        # Simulate rapid successive calls
        results = []
        5.times do
          results << repository.find_summary(account_id)
        end

        # Should only call underlying repository once
        expect(mock_underlying_repository).to have_received(:find_summary).once
        expect(results).to all(eq(sample_summary))
      end
    end
  end

  describe "performance characteristics" do
    let(:repository) do
      described_class.new(mock_client, underlying_repository: mock_underlying_repository)
    end

    context "when cache improves performance" do
      it "reduces calls to underlying repository through effective caching" do
        allow(mock_underlying_repository).to receive(:find_summary)
          .once
          .and_return(sample_summary)

        # Make multiple calls - should only hit underlying repository once
        10.times { repository.find_summary(account_id) }

        expect(mock_underlying_repository).to have_received(:find_summary).once
      end

      it "handles mixed data types efficiently" do
        allow(mock_underlying_repository).to receive(:find_summary).once.and_return(sample_summary)
        allow(mock_underlying_repository).to receive(:find_metadata).once.and_return(sample_metadata)
        allow(mock_underlying_repository).to receive(:find_positions).once.and_return(sample_positions)

        # Make calls to different data types
        repository.find_summary(account_id)
        repository.find_metadata(account_id)
        repository.find_positions(account_id, {})

        # Repeat calls should use cache
        repository.find_summary(account_id)
        repository.find_metadata(account_id)
        repository.find_positions(account_id, {})

        # Each type should only be called once
        expect(mock_underlying_repository).to have_received(:find_summary).once
        expect(mock_underlying_repository).to have_received(:find_metadata).once
        expect(mock_underlying_repository).to have_received(:find_positions).once
      end
    end

    context "when providing cache statistics" do
      it "reports meaningful cache statistics after usage" do
        # Use the cache
        allow(mock_underlying_repository).to receive(:find_summary).and_return(sample_summary)
        repository.find_summary(account_id)
        repository.find_summary(account_id) # Second call should hit cache

        stats = repository.cache_stats

        expect(stats[:total_entries]).to be > 0
        expect(stats[:cache_size_mb]).to be_a(Numeric)
        expect(stats[:oldest_entry]).to be_a(Time).or(be_nil)
      end
    end
  end

  describe "integration with different TTL configurations" do
    context "when using custom TTL settings for high-frequency trading" do
      let(:high_frequency_ttl) do
        {
          summary: 0.01,  # 10ms - Very short TTL for summary
          positions: 0.005, # 5ms - Extremely short TTL for positions
          metadata: 30    # 30s - Longer TTL for metadata
        }
      end

      let(:repository) do
        described_class.new(
          mock_client,
          underlying_repository: mock_underlying_repository,
          cache_ttl: high_frequency_ttl
        )
      end

      it "respects custom TTL settings for different data types" do
        # Set up mocks to verify different behaviors
        expect(mock_underlying_repository).to receive(:find_summary).twice.and_return(sample_summary)
        expect(mock_underlying_repository).to receive(:find_metadata).once.and_return(sample_metadata)

        # Initial calls
        repository.find_summary(account_id)
        repository.find_metadata(account_id)

        # Wait for short TTLs to expire
        sleep(0.02)

        # Summary should refetch due to short TTL, metadata should use cache
        repository.find_summary(account_id)
        repository.find_metadata(account_id)
      end
    end

    context "when using conservative TTL settings for stable data" do
      let(:conservative_ttl) do
        {
          summary: 30,      # 30 seconds
          metadata: 300,    # 5 minutes
          accounts: 180     # 3 minutes
        }
      end

      let(:repository) do
        described_class.new(
          mock_client,
          underlying_repository: mock_underlying_repository,
          cache_ttl: conservative_ttl
        )
      end

      it "caches data for longer periods with conservative settings" do
        expect(mock_underlying_repository).to receive(:discover_accounts).once.and_return(sample_accounts)
        expect(mock_underlying_repository).to receive(:find_summary).once.and_return(sample_summary)

        # Make multiple calls within TTL period
        repository.discover_accounts
        repository.find_summary(account_id)

        # Repeated calls should use cache
        repository.discover_accounts
        repository.find_summary(account_id)
      end
    end
  end
end
