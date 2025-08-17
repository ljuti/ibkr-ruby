# frozen_string_literal: true

require "faraday"
require "json"
require "zlib"
require "stringio"

module Ibkr
  module Http
    class Client
      attr_reader :config, :authenticator

      def initialize(config:, authenticator: nil)
        @config = config
        @authenticator = authenticator
      end

      def get(path, params: {}, headers: {})
        request(:get, path, params: params, headers: headers)
      end

      def post(path, body: {}, headers: {})
        request(:post, path, body: body, headers: headers)
      end

      def post_raw(path, body: {}, headers: {})
        request_raw(:post, path, body: body, headers: headers)
      end

      def put(path, body: {}, headers: {})
        request(:put, path, body: body, headers: headers)
      end

      def delete(path, headers: {})
        request(:delete, path, headers: headers)
      end

      private

      def request(method, path, params: {}, body: {}, headers: {})
        url = build_url(path)

        response = connection.send(method) do |req|
          req.url path
          req.headers.update(headers)
          req.headers["Authorization"] = authorization_header(method, url, params, body) if needs_auth?(path)

          case method
          when :get, :delete
            req.params = params
          when :post, :put
            req.headers["Content-Type"] = "application/json"
            req.body = body.to_json unless body.empty?
          end
        end

        handle_response(response)
      rescue Faraday::Error => e
        raise Ibkr::ApiError, "HTTP request failed: #{e.message}"
      end

      def request_raw(method, path, params: {}, body: {}, headers: {})
        url = build_url(path)

        connection.send(method) do |req|
          req.url path
          req.headers.update(headers)
          req.headers["Authorization"] = authorization_header(method, url, params, body) if needs_auth?(path)

          case method
          when :get, :delete
            req.params = params
          when :post, :put
            req.headers["Content-Type"] = "application/json"
            req.body = body.to_json unless body.empty?
          end
        end

      # Return raw response without parsing
      rescue Faraday::Error => e
        raise Ibkr::ApiError, "HTTP request failed: #{e.message}"
      end

      def connection
        @connection ||= Faraday.new(url: config.base_url) do |conn|
          conn.headers["User-Agent"] = config.user_agent
          conn.headers["Accept"] = "application/json"
          conn.headers["Accept-Encoding"] = "gzip,deflate"
          conn.headers["Connection"] = "keep-alive"

          # Note: Retry middleware commented out due to dependency issues
          # conn.request :retry, max: config.retries, retry_statuses: [429, 500, 502, 503, 504]
          conn.options.timeout = config.timeout

          conn.adapter Faraday.default_adapter
        end
      end

      def build_url(path)
        path = "/#{path}" unless path.start_with?("/")
        "#{config.base_url}#{path}"
      end

      def needs_auth?(path)
        !path.include?("/oauth/live_session_token") || @authenticator
      end

      def authorization_header(method, url, params, body)
        return nil unless @authenticator

        if url.include?("/oauth/live_session_token")
          "OAuth #{@authenticator.oauth_header_for_authentication}"
        else
          query_params = (method == :get) ? params : {}
          request_body = [:post, :put].include?(method) ? body : {}

          "OAuth #{@authenticator.oauth_header_for_api_request(
            method: method.to_s.upcase,
            url: url.split("?").first,
            query: query_params,
            body: request_body
          )}"
        end
      end

      def handle_response(response)
        # Handle different response scenarios
        case response.status
        when 200..299
          parse_successful_response(response)
        when 401
          raise Ibkr::AuthenticationError.from_response(response, context: build_error_context(response))
        when 429
          raise Ibkr::RateLimitError.from_response(response, context: build_error_context(response))
        when 400..499
          raise Ibkr::ApiError.from_response(response, context: build_error_context(response))
        when 500..599
          raise Ibkr::ApiError::ServerError.from_response(response, context: build_error_context(response))
        else
          raise Ibkr::ApiError.from_response(response, context: build_error_context(response))
        end
      end

      def parse_successful_response(response)
        content = decompress_if_needed(response)

        return nil if content.nil? || content.empty?

        # Try to parse as JSON, return raw content if it fails
        begin
          JSON.parse(content)
        rescue JSON::ParserError
          content
        end
      end

      def decompress_if_needed(response)
        content = response.body
        encoding = response.headers["content-encoding"]

        if encoding&.include?("gzip")
          Zlib::GzipReader.new(StringIO.new(content)).read
        elsif encoding&.include?("deflate")
          Zlib::Inflate.inflate(content)
        else
          content
        end
      rescue Zlib::Error => e
        raise Ibkr::ApiError, "Failed to decompress response: #{e.message}"
      end

      def build_error_context(response)
        {
          endpoint: response.respond_to?(:env) && response.env&.[](:url)&.path,
          method: response.respond_to?(:env) && response.env&.[](:method)&.to_s&.upcase,
          response_status: response.status,
          request_id: response.headers["X-Request-ID"],
          user_agent: response.respond_to?(:env) && response.env&.[](:request_headers)&.[]("User-Agent"),
          content_type: response.headers["Content-Type"],
          content_length: response.headers["Content-Length"],
          retry_after: response.headers["Retry-After"]
        }.compact
      end

      # Wrapper class for response objects
      class Response
        attr_reader :status, :headers, :body, :parsed_body

        def initialize(faraday_response, parsed_body = nil)
          @status = faraday_response.status
          @headers = faraday_response.headers
          @body = faraday_response.body
          @parsed_body = parsed_body
        end

        def success?
          (200..299).cover?(status)
        end

        def data
          parsed_body || body
        end
      end
    end
  end
end
