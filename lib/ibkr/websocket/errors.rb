# frozen_string_literal: true

require_relative "../errors/base"

module Ibkr
  module WebSocket
    # Base class for all WebSocket-related errors
    class BaseError < Ibkr::BaseError
      def initialize(message = nil, code: nil, details: nil, response: nil, context: {}, cause: nil)
        super(message, code: code, details: details, response: response, context: context)
        @cause = cause
      end

      attr_reader :cause

      # Generate WebSocket-specific error suggestions
      def generate_suggestions
        suggestions = super

        case self.class.name
        when /Connection/
          suggestions.concat([
            "Check network connectivity and firewall settings",
            "Verify WebSocket endpoint is accessible (wss://api.ibkr.com/v1/api/ws)",
            "Ensure OAuth authentication is valid and not expired",
            "Try reconnecting with exponential backoff"
          ])
        when /Subscription/
          suggestions.concat([
            "Check subscription limits for your account type",
            "Verify symbol formats and availability",
            "Reduce subscription frequency if rate limited",
            "Use unsubscribe before resubscribing to same data"
          ])
        when /Authentication/
          suggestions.concat([
            "Verify OAuth credentials are properly configured",
            "Check if WebSocket authentication token is valid",
            "Ensure HTTP authentication completed before WebSocket connection",
            "Try re-authenticating the main client first"
          ])
        end

        suggestions.uniq
      end
    end

    # Connection-related errors
    class ConnectionError < BaseError
      def self.connection_failed(message, context: {}, cause: nil)
        new(
          message,
          context: context.merge(
            operation: "websocket_connection",
            category: "connection"
          ),
          cause: cause
        )
      end

      def self.authentication_failed(message, context: {}, cause: nil)
        new(
          message,
          context: context.merge(
            operation: "websocket_authentication",
            category: "authentication"
          ),
          cause: cause
        )
      end

      def self.reconnection_failed(message, context: {}, cause: nil)
        new(
          message,
          context: context.merge(
            operation: "websocket_reconnection",
            category: "connection"
          ),
          cause: cause
        )
      end
    end

    # Subscription management errors
    class SubscriptionError < BaseError
      def self.limit_exceeded(subscription_type, context: {})
        new(
          "Subscription limit exceeded for #{subscription_type}",
          context: context.merge(
            operation: "subscription_management",
            subscription_type: subscription_type,
            category: "limit_exceeded"
          )
        )
      end

      def self.already_subscribed(subscription_key, context: {})
        new(
          "Already subscribed to #{subscription_key}",
          context: context.merge(
            operation: "subscription_management",
            subscription_key: subscription_key,
            category: "duplicate_subscription"
          )
        )
      end

      def self.rate_limited(context: {})
        new(
          "Subscription rate limit exceeded",
          context: context.merge(
            operation: "subscription_rate_limiting",
            category: "rate_limit"
          )
        )
      end

      def self.subscription_failed(message, context: {})
        new(
          "Subscription failed: #{message}",
          context: context.merge(
            operation: "subscription_creation",
            category: "subscription_failure"
          )
        )
      end
    end

    # Authentication-specific errors
    class AuthenticationError < BaseError
      def self.not_authenticated(context: {})
        new(
          "WebSocket client not authenticated",
          context: context.merge(
            operation: "websocket_authentication_check",
            category: "authentication_required"
          )
        )
      end

      def self.token_expired(context: {})
        new(
          "WebSocket authentication token expired",
          context: context.merge(
            operation: "websocket_token_validation",
            category: "token_expired"
          )
        )
      end

      def self.invalid_credentials(context: {})
        new(
          "Invalid WebSocket authentication credentials",
          context: context.merge(
            operation: "websocket_authentication",
            category: "invalid_credentials"
          )
        )
      end
    end

    # Message processing errors
    class MessageProcessingError < BaseError
      def self.invalid_message_format(message, context: {})
        new(
          "Invalid WebSocket message format: #{message}",
          context: context.merge(
            operation: "message_processing",
            category: "invalid_format"
          )
        )
      end

      def self.message_routing_failed(message, context: {}, cause: nil)
        new(
          "Failed to route WebSocket message: #{message}",
          context: context.merge(
            operation: "message_routing",
            category: "routing_failure"
          ),
          cause: cause
        )
      end
    end

    # Event handling errors
    class EventError < BaseError
      def self.handler_failed(message, context: {}, cause: nil)
        new(
          message,
          context: context.merge(
            operation: "event_handler_execution",
            category: "handler_failure"
          ),
          cause: cause
        )
      end
    end

    # Reconnection strategy errors
    class ReconnectionError < BaseError
      def self.max_attempts_exceeded(attempts, context: {})
        new(
          "Maximum reconnection attempts (#{attempts}) exceeded",
          context: context.merge(
            operation: "websocket_reconnection",
            category: "max_attempts_exceeded",
            attempts: attempts
          )
        )
      end

      def self.reconnection_timeout(context: {})
        new(
          "Reconnection attempt timed out",
          context: context.merge(
            operation: "websocket_reconnection",
            category: "timeout"
          )
        )
      end
    end

    # Circuit breaker errors
    class CircuitBreakerError < BaseError
      def self.circuit_open(context: {})
        new(
          "Circuit breaker is open - too many recent failures",
          context: context.merge(
            operation: "circuit_breaker_check",
            category: "circuit_open"
          )
        )
      end
    end
  end
end
