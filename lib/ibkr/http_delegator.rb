# frozen_string_literal: true

module Ibkr
  # Module for delegating HTTP operations to an OAuth client.
  #
  # This module provides a clean way to delegate HTTP methods to an OAuth client
  # without repeating the delegation logic. It eliminates code duplication and
  # provides a consistent interface for HTTP operations.
  #
  # @example
  #   class MyClient
  #     include Ibkr::HttpDelegator
  #
  #     private
  #
  #     def http_client
  #       @oauth_client
  #     end
  #   end
  #
  module HttpDelegator
    # Delegate GET request to the HTTP client.
    #
    # @param path [String] The API endpoint path
    # @param options [Hash] Request options (params, headers, etc.)
    # @return [Hash] Parsed response body
    def get(path, **options)
      http_client.get(path, **options)
    end

    # Delegate POST request to the HTTP client.
    #
    # @param path [String] The API endpoint path
    # @param options [Hash] Request options (body, headers, etc.)
    # @return [Hash] Parsed response body
    def post(path, **options)
      http_client.post(path, **options)
    end

    # Delegate PUT request to the HTTP client.
    #
    # @param path [String] The API endpoint path
    # @param options [Hash] Request options (body, headers, etc.)
    # @return [Hash] Parsed response body
    def put(path, **options)
      http_client.put(path, **options)
    end

    # Delegate DELETE request to the HTTP client.
    #
    # @param path [String] The API endpoint path
    # @param options [Hash] Request options (headers, etc.)
    # @return [Hash] Parsed response body
    def delete(path, **options)
      http_client.delete(path, **options)
    end

    private

    # Abstract method that must be implemented by including classes.
    #
    # @return [Object] The HTTP client object that responds to HTTP methods
    # @raise [NotImplementedError] if not implemented by including class
    def http_client
      raise NotImplementedError, "Including class must implement #http_client method"
    end
  end
end
