# frozen_string_literal: true

require_relative "../errors/repository_error"

module Ibkr
  module Repositories
    # Abstract base class for all repositories
    # Defines the contract that all repositories must implement
    class BaseRepository
      def initialize(client)
        @client = client
      end

      protected

      attr_reader :client

      # Template method for common error handling
      def with_error_handling
        yield
      rescue Ibkr::BaseError
        # Re-raise IBKR-specific errors as they have useful context
        raise
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        # Re-raise network errors directly for test compatibility
        raise e
      rescue => e
        # Wrap other errors in repository-specific errors
        raise Ibkr::RepositoryError, "Repository operation failed: #{e.message}"
      end

      # Helper method to ensure client is authenticated
      def ensure_authenticated!
        unless client.authenticated?
          raise Ibkr::AuthenticationError, "Client must be authenticated for repository operations"
        end
      end

      # Helper method to get current account ID
      def current_account_id
        client.active_account_id || raise(Ibkr::ConfigurationError, "No active account set")
      end
    end
  end
end
