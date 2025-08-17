# frozen_string_literal: true

require_relative "api_account_repository"
require_relative "cached_account_repository"
require_relative "test_account_repository"

module Ibkr
  module Repositories
    # Factory for creating repository instances based on configuration
    class RepositoryFactory
      REPOSITORY_TYPES = {
        api: ApiAccountRepository,
        cached: CachedAccountRepository,
        test: TestAccountRepository
      }.freeze

      class << self
        # Create an account repository based on configuration
        def create_account_repository(client, type: nil, options: {})
          repository_type = determine_repository_type(type, client)

          case repository_type
          when :api
            ApiAccountRepository.new(client)
          when :cached
            underlying_repo = options[:underlying_repository] || ApiAccountRepository.new(client)
            CachedAccountRepository.new(
              client,
              underlying_repository: underlying_repo,
              cache_ttl: options[:cache_ttl] || {}
            )
          when :test
            TestAccountRepository.new(client, test_data: options[:test_data])
          else
            raise Ibkr::RepositoryError.unsupported_repository_type(
              repository_type,
              context: {available_types: REPOSITORY_TYPES.keys}
            )
          end
        end

        # Create a repository with automatic type detection based on environment
        def create_auto_repository(client, options: {})
          type = detect_optimal_repository_type(client)
          create_account_repository(client, type: type, options: options)
        end

        # Create a repository chain (e.g., cached -> API)
        def create_repository_chain(client, chain_config)
          chain_config.reverse.reduce(nil) do |underlying, config|
            type = config[:type]
            options = config[:options] || {}
            options[:underlying_repository] = underlying if underlying

            create_account_repository(client, type: type, options: options)
          end
        end

        private

        def determine_repository_type(type, client)
          # Explicit type takes precedence
          return type.to_sym if type

          # Check client configuration
          if client.respond_to?(:config) && client.config.respond_to?(:repository_type)
            return client.config.repository_type.to_sym
          end

          # Check global configuration
          if Ibkr.configuration.respond_to?(:repository_type)
            return Ibkr.configuration.repository_type.to_sym
          end

          # Default to API repository
          :api
        end

        def detect_optimal_repository_type(client)
          # In test environment, prefer test repository only if explicitly requested
          if defined?(Rails) && Rails.respond_to?(:env) && Rails.env.test? && ENV["IBKR_USE_TEST_REPOSITORY"] == "true"
            return :test
          end

          # Check if explicitly requested to use test mode
          if ENV["IBKR_TEST_MODE"] == "true" || ENV["IBKR_USE_TEST_REPOSITORY"] == "true"
            return :test
          end

          # For production/development, prefer cached repository for performance
          if client.instance_variable_get(:@live) == false # Sandbox mode
            :cached
          else
            :api  # Live trading should use direct API calls
          end
        end
      end
    end
  end
end
