# frozen_string_literal: true

module Ibkr
  # Error class for repository-related operations
  class RepositoryError < BaseError
    # Repository operation failed due to data access issues
    def self.data_access_failed(message, context: {})
      new(
        message,
        code: "REPOSITORY_DATA_ACCESS_FAILED",
        details: context.merge(
          category: "repository",
          operation: "data_access"
        )
      )
    end

    # Repository configuration is invalid
    def self.invalid_configuration(message, context: {})
      new(
        message,
        code: "REPOSITORY_INVALID_CONFIG",
        details: context.merge(
          category: "repository",
          operation: "configuration"
        )
      )
    end

    # Repository cache operation failed
    def self.cache_operation_failed(message, context: {})
      new(
        message,
        code: "REPOSITORY_CACHE_FAILED",
        details: context.merge(
          category: "repository",
          operation: "cache"
        )
      )
    end
  end
end
