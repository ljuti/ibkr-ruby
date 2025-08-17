# frozen_string_literal: true

module Ibkr
  class RateLimitError < BaseError
    attr_reader :retry_after, :limit, :remaining, :reset_time

    def initialize(message = "Rate limit exceeded", retry_after: nil, limit: nil, remaining: nil, reset_time: nil, **options)
      super(message, **options)
      @retry_after = retry_after
      @limit = limit
      @remaining = remaining
      @reset_time = reset_time
    end

    def to_h
      super.merge(
        retry_after: retry_after,
        limit: limit,
        remaining: remaining,
        reset_time: reset_time
      ).compact
    end

    # Factory method to extract rate limit info from response headers
    def self.from_response(response, message: nil)
      headers = response.headers

      retry_after = headers["Retry-After"]&.to_i
      limit = headers["X-RateLimit-Limit"]&.to_i
      remaining = headers["X-RateLimit-Remaining"]&.to_i
      reset_time = headers["X-RateLimit-Reset"]&.then { |t| Time.at(t.to_i) }

      error_message = message || build_rate_limit_message(retry_after, remaining, reset_time)

      new(
        error_message,
        retry_after: retry_after,
        limit: limit,
        remaining: remaining,
        reset_time: reset_time,
        response: response
      )
    end

    class << self
      private

      def build_rate_limit_message(retry_after, remaining, reset_time)
        message = "Rate limit exceeded"

        if retry_after
          message += ". Retry after #{retry_after} seconds"
        elsif reset_time
          message += ". Rate limit resets at #{reset_time}"
        end

        if remaining
          message += ". #{remaining} requests remaining"
        end

        message
      end
    end
  end
end
