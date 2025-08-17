# frozen_string_literal: true

require_relative "base_repository"
require_relative "account_repository_interface"

module Ibkr
  module Repositories
    # Cached implementation of AccountRepository
    # Wraps another repository with caching capabilities
    class CachedAccountRepository < BaseRepository
      include AccountRepositoryInterface

      # Default cache expiration times (in seconds)
      DEFAULT_CACHE_TTL = {
        summary: 30,      # Account summary changes less frequently
        metadata: 300,    # Account metadata rarely changes
        positions: 10,    # Positions change more frequently
        transactions: 60, # Transaction history is relatively stable
        accounts: 60      # Available accounts rarely change
      }.freeze

      def initialize(client, underlying_repository: nil, cache_ttl: {})
        super(client)
        @underlying_repository = underlying_repository || ApiAccountRepository.new(client)
        @cache_ttl = DEFAULT_CACHE_TTL.merge(cache_ttl)
        @cache = {}
        @cache_timestamps = {}
      end

      def find_summary(account_id)
        cache_key = "summary:#{account_id}"

        if cache_valid?(cache_key, @cache_ttl[:summary])
          @cache[cache_key]
        else
          result = @underlying_repository.find_summary(account_id)
          store_in_cache(cache_key, result)
          result
        end
      end

      def find_metadata(account_id)
        cache_key = "metadata:#{account_id}"

        if cache_valid?(cache_key, @cache_ttl[:metadata])
          @cache[cache_key]
        else
          result = @underlying_repository.find_metadata(account_id)
          store_in_cache(cache_key, result)
          result
        end
      end

      def find_positions(account_id, options = {})
        # Include options in cache key to handle different queries
        cache_key = "positions:#{account_id}:#{options.hash}"

        if cache_valid?(cache_key, @cache_ttl[:positions])
          @cache[cache_key]
        else
          result = @underlying_repository.find_positions(account_id, options)
          store_in_cache(cache_key, result)
          result
        end
      end

      def find_transactions(account_id, contract_id, days = 90)
        cache_key = "transactions:#{account_id}:#{contract_id}:#{days}"

        if cache_valid?(cache_key, @cache_ttl[:transactions])
          @cache[cache_key]
        else
          result = @underlying_repository.find_transactions(account_id, contract_id, days)
          store_in_cache(cache_key, result)
          result
        end
      end

      def discover_accounts
        cache_key = "accounts:discovery"

        if cache_valid?(cache_key, @cache_ttl[:accounts])
          @cache[cache_key]
        else
          result = @underlying_repository.discover_accounts
          store_in_cache(cache_key, result)
          result
        end
      end

      def account_exists?(account_id)
        # Check cache first, then delegate
        available_accounts = discover_accounts
        available_accounts.include?(account_id)
      end

      # Cache management methods

      def clear_cache
        @cache.clear
        @cache_timestamps.clear
      end

      def clear_cache_for_account(account_id)
        keys_to_remove = @cache.keys.select { |key| key.include?(account_id) }
        keys_to_remove.each do |key|
          @cache.delete(key)
          @cache_timestamps.delete(key)
        end
      end

      def cache_stats
        {
          total_entries: @cache.size,
          cache_hit_ratio: calculate_hit_ratio,
          oldest_entry: oldest_cache_entry,
          cache_size_mb: calculate_cache_size
        }
      end

      private

      def cache_valid?(key, ttl_seconds)
        return false unless @cache.key?(key)
        return false unless @cache_timestamps.key?(key)

        age = Time.now - @cache_timestamps[key]
        age < ttl_seconds
      end

      def store_in_cache(key, value)
        @cache[key] = value
        @cache_timestamps[key] = Time.now

        # Clean up old entries if cache gets too large
        cleanup_cache if @cache.size > 1000
      end

      def cleanup_cache
        # Remove entries older than their TTL
        current_time = Time.now

        @cache_timestamps.each do |key, timestamp|
          # Determine TTL based on key type
          ttl = determine_ttl_for_key(key)

          if current_time - timestamp > ttl
            @cache.delete(key)
            @cache_timestamps.delete(key)
          end
        end
      end

      def determine_ttl_for_key(key)
        case key
        when /^summary:/ then @cache_ttl[:summary]
        when /^metadata:/ then @cache_ttl[:metadata]
        when /^positions:/ then @cache_ttl[:positions]
        when /^transactions:/ then @cache_ttl[:transactions]
        when /^accounts:/ then @cache_ttl[:accounts]
        else 60 # Default TTL
        end
      end

      def calculate_hit_ratio
        return 0.0 if @cache_access_count.nil? || @cache_access_count == 0

        @cache_hit_count.to_f / @cache_access_count.to_f
      end

      def oldest_cache_entry
        return nil if @cache_timestamps.empty?

        @cache_timestamps.values.min
      end

      def calculate_cache_size
        # Rough estimation of cache size in MB
        cache_string = @cache.to_s
        (cache_string.bytesize / 1024.0 / 1024.0).round(2)
      end
    end
  end
end
