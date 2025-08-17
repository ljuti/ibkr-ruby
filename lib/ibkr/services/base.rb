# frozen_string_literal: true

module Ibkr
  module Services
    class Base
      attr_reader :client

      def initialize(client)
        @client = client
      end

      protected

      # Delegate HTTP methods to client
      def get(path, **options)
        client.get(path, **options)
      end

      def post(path, **options)
        client.post(path, **options)
      end

      def put(path, **options)
        client.put(path, **options)
      end

      def delete(path, **options)
        client.delete(path, **options)
      end

      # Helper to ensure authentication
      def ensure_authenticated!
        unless client.authenticated?
          raise Ibkr::AuthenticationError, "Client must be authenticated before making API calls"
        end
      end

      # Helper to get current account ID
      def account_id
        client.account_id
      end

      # Transform response data using a model class
      def transform_response(response, model_class)
        case response
        when Array
          response.map { |item| model_class.new(item) }
        when Hash
          model_class.new(response)
        else
          response
        end
      end

      # Build path with account ID
      def account_path(path)
        "/v1/api/portfolio/#{account_id}#{path}"
      end

      # Build general API path
      def api_path(path)
        "/v1/api#{path}"
      end
    end
  end
end
