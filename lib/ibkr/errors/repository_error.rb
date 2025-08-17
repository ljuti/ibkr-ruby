# frozen_string_literal: true

module Ibkr
  # Error class for repository-related operations
  class RepositoryError < BaseError
    # Repository operation failed due to data access issues
    def self.data_access_failed(message, context: {})
      with_context(
        message,
        code: "REPOSITORY_DATA_ACCESS_FAILED",
        context: context.merge(
          category: "repository",
          operation: "data_access"
        )
      )
    end

    # Repository configuration is invalid
    def self.invalid_configuration(message, context: {})
      with_context(
        message,
        code: "REPOSITORY_INVALID_CONFIG",
        context: context.merge(
          category: "repository",
          operation: "configuration"
        )
      )
    end

    # Repository cache operation failed
    def self.cache_operation_failed(message, context: {})
      with_context(
        message,
        code: "REPOSITORY_CACHE_FAILED",
        context: context.merge(
          category: "repository",
          operation: "cache"
        )
      )
    end

    # Repository type not supported
    def self.unsupported_repository_type(repository_type, context: {})
      with_context(
        "Repository type '#{repository_type}' is not supported",
        code: "REPOSITORY_UNSUPPORTED_TYPE",
        context: context.merge(
          category: "repository",
          operation: "factory_creation",
          repository_type: repository_type
        )
      )
    end

    # Repository data not found
    def self.data_not_found(resource, identifier, context: {})
      with_context(
        "#{resource} with identifier '#{identifier}' not found in repository",
        code: "REPOSITORY_DATA_NOT_FOUND",
        context: context.merge(
          category: "repository",
          operation: "data_retrieval",
          resource: resource,
          identifier: identifier
        )
      )
    end
  end
end
