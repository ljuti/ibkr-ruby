# frozen_string_literal: true

module Ibkr
  module FlexError
    class Base < Ibkr::BaseError
      attr_reader :error_code, :query_id, :reference_code

      def initialize(message, error_code: nil, code: nil, query_id: nil, reference_code: nil, context: {}, details: nil, **extra_args)
        @error_code = error_code || code
        @query_id = query_id
        @reference_code = reference_code
        @details = details || context || {}
        
        enhanced_context = @details.merge(
          error_code: @error_code,
          query_id: query_id,
          reference_code: reference_code
        ).merge(extra_args).compact
        
        super(message, context: enhanced_context)
      end
      
      def details
        @details
      end
      
      def code
        @error_code
      end

      def to_h
        super.merge(
          error_code: error_code,
          query_id: query_id,
          reference_code: reference_code,
          suggestions: suggestions
        ).compact
      end

      def suggestions
        [
          "Verify Flex Web Service token is configured",
          "Check Client Portal Flex Queries section",
          "Ensure IBKR system status is operational",
          "Review Flex Web Service documentation"
        ]
      end
    end

    class ConfigurationError < Base
      def suggestions
        [
          "Ensure Flex Web Service token is configured",
          "Verify token is valid and not expired",
          "Check token permissions in Client Portal",
          "Token should be in config.flex_token or IBKR_FLEX_TOKEN env var"
        ]
      end
    end

    class QueryNotFound < Base
      def suggestions
        [
          "Verify query ID exists in Client Portal",
          "Check query ID format (should be numeric)",
          "Ensure query is active and not deleted",
          "Query must be created under same account as token"
        ]
      end
    end

    class ReportNotReady < Base
      attr_reader :retry_after

      def initialize(message, retry_after: 5, **kwargs)
        @retry_after = retry_after
        super(message, **kwargs)
      end

      def retryable?
        true
      end

      def suggestions
        [
          "Report is still being generated",
          "Retry after #{retry_after} seconds",
          "Large reports may take longer to process",
          "Consider implementing exponential backoff"
        ]
      end
    end

    class InvalidReference < Base
      def suggestions
        [
          "Reference code may have expired",
          "Verify reference code format",
          "Reports are available for limited time",
          "Generate a new report if reference is expired"
        ]
      end
    end

    class NetworkError < Base
      def suggestions
        [
          "Check network connectivity",
          "Verify IBKR Flex service is accessible",
          "Check firewall/proxy settings",
          "Retry with exponential backoff"
        ]
      end
    end

    class ParseError < Base
      attr_reader :xml_content

      def initialize(message, xml_content: nil, **kwargs)
        @xml_content = xml_content
        super(message, **kwargs)
      end

      def suggestions
        [
          "XML response may be malformed",
          "Check IBKR API version compatibility",
          "Report format may have changed",
          "Enable debug logging for raw response"
        ]
      end
    end

    class ApiError < Base
      def suggestions
        [
          "Check IBKR Flex service status",
          "Verify API endpoint is correct",
          "Review error code documentation",
          "Contact IBKR support if issue persists"
        ]
      end
    end

    class RateLimitError < Base
      attr_reader :retry_after

      def initialize(message, retry_after: 60, **kwargs)
        @retry_after = retry_after
        super(message, **kwargs)
      end

      def retryable?
        true
      end

      def suggestions
        [
          "Too many requests sent",
          "Wait #{retry_after} seconds before retrying",
          "Implement request throttling",
          "Cache reports when possible"
        ]
      end
    end
  end
end