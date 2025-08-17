# frozen_string_literal: true

require "base64"
require "openssl"

module Ibkr
  module Oauth
    class LiveSessionToken
      attr_reader :token, :signature, :expires_in

      # Test-specific accessor for signature (already public but making it explicit)
      # This allows tests to verify the signature was computed correctly

      def initialize(token, signature, expires_in)
        @token = token
        @signature = signature
        @expires_in = expires_in
      end

      def expired?
        return false if expires_in.nil?

        Time.now > expiration_time
      rescue ArgumentError => e
        # Invalid expiration time format
        log_error("Invalid expiration time: #{e.message}")
        true
      end

      def valid?(consumer_key = nil)
        return false if expired?
        return false if token.nil? || signature.nil?

        # If no consumer key provided, try to get from Rails credentials
        consumer_key ||= extract_consumer_key
        return false if consumer_key.nil?

        valid_signature?(consumer_key)
      end

      def expiration_time
        return nil if expires_in.nil?

        # Validate that expires_in is a reasonable timestamp
        if expires_in.is_a?(String) && expires_in !~ /^\d+$/
          raise ArgumentError, "Invalid timestamp format: #{expires_in}"
        end

        # Handle both seconds and milliseconds timestamps
        timestamp = expires_in.to_i
        timestamp /= 1000 if timestamp > 4_000_000_000

        Time.at(timestamp)
      end

      def time_until_expiry
        return nil if expires_in.nil?

        [expiration_time - Time.now, 0].max
      end

      def to_h
        {
          token: token,
          signature: signature,
          expires_in: expires_in,
          expired: expired?,
          expiration_time: expiration_time,
          time_until_expiry: time_until_expiry
        }
      end

      # Make these methods public for testing
      def valid_signature?(consumer_key = nil)
        consumer_key ||= extract_consumer_key
        return false if consumer_key.nil? || consumer_key.empty?

        key_bytes = Base64.decode64(token)
        expected_hex = OpenSSL::HMAC.hexdigest(
          "sha1",
          key_bytes,
          consumer_key.encode("utf-8")
        ).downcase

        secure_compare(expected_hex, signature.downcase)
      rescue ArgumentError, OpenSSL::HMACError
        false
      end

      # Constant-time string comparison to prevent timing attacks
      def secure_compare(a, b)
        # Use ActiveSupport if available, fallback to custom implementation
        if defined?(ActiveSupport::SecurityUtils)
          ActiveSupport::SecurityUtils.secure_compare(a, b)
        else
          return false if a.nil? || b.nil? || a.length != b.length

          result = 0
          a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
          result == 0
        end
      rescue ArgumentError
        false
      end

      private

      def extract_consumer_key
        # Try to get consumer key from Rails credentials if available
        if defined?(Rails) && Rails.respond_to?(:application)
          Rails.application.credentials.dig(:ibkr, :oauth, :consumer_key)
        end
      rescue
        nil
      end

      def log_error(message)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error(message)
        end
      end
    end
  end
end
