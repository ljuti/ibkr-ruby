# frozen_string_literal: true

module Ibkr
  class BaseError < StandardError
    attr_reader :code, :details, :response, :context

    def initialize(message = nil, code: nil, details: nil, response: nil, context: {})
      super(message)
      @code = code
      @details = details || {}
      @response = response
      @context = context || {}

      # Automatically capture additional context
      capture_context!
    end

    # Extract useful information from HTTP response
    def self.from_response(response, message: nil)
      details = extract_error_details(response)
      error_message = message || details[:message] || default_message_for_status(response.status)

      new(
        error_message,
        code: details[:code] || response.status,
        details: details,
        response: response
      )
    end

    def to_h
      {
        error: self.class.name,
        message: message,
        code: code,
        details: details,
        context: context,
        suggestions: suggestions,
        debug_info: debug_info
      }.compact
    end

    # Generate helpful suggestions based on error type and context
    def suggestions
      @suggestions ||= generate_suggestions
    end

    # Provide debug information for troubleshooting
    def debug_info
      @debug_info ||= generate_debug_info
    end

    # Enhanced error message with context
    def detailed_message
      parts = [message]

      if context[:endpoint]
        parts << "Endpoint: #{context[:endpoint]}"
      end

      if context[:account_id]
        parts << "Account: #{context[:account_id]}"
      end

      if context[:retry_count] && context[:retry_count] > 0
        parts << "Retries attempted: #{context[:retry_count]}"
      end

      suggestion_list = suggestions
      if suggestion_list&.any?
        parts << "\nSuggestions:"
        suggestion_list.each { |suggestion| parts << "  - #{suggestion}" }
      end

      parts.join("\n")
    end

    # Create error with rich context
    def self.with_context(message, context: {}, **options)
      new(message, context: context, **options)
    end

    class << self
      private

      def extract_error_details(response)
        return {} unless response&.body

        begin
          parsed = JSON.parse(response.body)
          {
            message: parsed["error"] || parsed["message"] || parsed["errorMessage"],
            code: parsed["code"] || parsed["errorCode"],
            request_id: parsed["requestId"] || response.headers["X-Request-ID"],
            raw_response: parsed
          }
        rescue JSON::ParserError
          {
            message: response.body.to_s.strip[0, 200], # First 200 chars
            raw_response: response.body
          }
        end
      end

      def default_message_for_status(status)
        case status
        when 400
          "Bad request - invalid parameters"
        when 401
          "Authentication failed"
        when 403
          "Forbidden - insufficient permissions"
        when 404
          "Resource not found"
        when 429
          "Rate limit exceeded"
        when 500..599
          "Server error occurred"
        else
          "HTTP request failed with status #{status}"
        end
      end
    end

    private

    def capture_context!
      @context.merge!(
        timestamp: Time.now.iso8601,
        thread_id: Thread.current.object_id,
        ibkr_version: Ibkr::VERSION
      )

      # Capture call stack information (first few non-error frames)
      relevant_frames = caller.reject { |frame| frame.include?("/errors/") }
      @context[:caller_location] = relevant_frames.first(3) if relevant_frames.any?
    end

    def generate_suggestions
      suggestions = []

      case self.class.name
      when /Authentication/
        suggestions << "Verify your OAuth credentials are correct"
        suggestions << "Check if your session has expired"
        suggestions << "Ensure your system clock is synchronized"
      when /RateLimit/
        suggestions << "Implement exponential backoff in your retry logic"
        suggestions << "Reduce the frequency of API calls"
        suggestions << "Consider caching responses to minimize API usage"
      when /Configuration/
        suggestions << "Check your configuration file for missing or invalid values"
        suggestions << "Verify file paths exist and are readable"
        suggestions << "Ensure environment variables are set correctly"
      when /Repository/
        suggestions << "Check if the repository type is supported"
        suggestions << "Verify the underlying data source is accessible"
        suggestions << "Try switching to a different repository implementation"
      end

      # Context-specific suggestions
      if context[:endpoint]
        case context[:endpoint]
        when %r{/iserver/accounts}
          suggestions << "Ensure you're authenticated before fetching accounts"
          suggestions << "Verify your account has proper permissions"
        when %r{/portfolio}
          suggestions << "Check that the account ID is valid and accessible"
          suggestions << "Ensure the account has positions or data to retrieve"
        end
      end

      if context[:account_id] && context[:account_id].empty?
        suggestions << "Provide a valid account ID"
        suggestions << "Use client.available_accounts to see available account IDs"
      end

      # Add suggestions for account lookup/switching operations
      if context[:operation]&.include?("account")
        suggestions << "Use client.available_accounts to see available account IDs"
        suggestions << "Ensure the account is valid and accessible"
      end

      suggestions.uniq
    end

    def generate_debug_info
      info = {
        error_class: self.class.name,
        timestamp: context[:timestamp]
      }

      if response
        info[:http_status] = response.status
        info[:response_headers] = response.headers.to_h
        info[:request_id] = response.headers["X-Request-ID"] || details[:request_id]
      end

      if context[:endpoint]
        info[:endpoint] = context[:endpoint]
      end

      if context[:retry_count]
        info[:retry_count] = context[:retry_count]
      end

      info
    end
  end
end
