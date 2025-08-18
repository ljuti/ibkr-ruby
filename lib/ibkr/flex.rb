# frozen_string_literal: true

require "faraday"
require_relative "flex_parser"
require_relative "errors/flex_error"
require_relative "models/flex_report"

module Ibkr
  # Client for IBKR Flex Web Service
  #
  # The Flex Web Service provides access to pre-configured reports that you set up
  # in IBKR Client Portal. These reports can include trading activity, positions,
  # cash balances, and performance metrics.
  #
  # @example Basic usage
  #   flex = Ibkr::Flex.new(token: "your_flex_token")
  #   report = flex.generate_and_fetch("123456")
  #
  # @example With client integration
  #   client = Ibkr::Client.new(default_account_id: "DU123456")
  #   report = client.flex.generate_and_fetch("123456")
  #
  class Flex
    attr_reader :token, :config, :client

    # Flex API version to use
    FLEX_API_VERSION = 3

    # Base URL for Flex Web Service endpoints
    FLEX_BASE_URL = "https://ndcdyn.interactivebrokers.com"

    # Maximum number of retries for report generation
    MAX_RETRIES = 10

    # Delay in seconds between retries
    RETRY_DELAY = 5

    # Initialize a new Flex client
    #
    # @param token [String, nil] Flex Web Service token
    # @param config [Ibkr::Configuration, nil] Configuration object
    # @param client [Ibkr::Client, nil] Parent client instance
    #
    # @raise [FlexError::ConfigurationError] if token is not configured
    def initialize(token: nil, config: nil, client: nil)
      @client = client
      @config = config || client&.config || Ibkr.configuration
      @token = token || @config.flex_token || fetch_token_from_credentials

      validate_configuration!
    end

    # Generate a Flex report (Step 1 of 2)
    #
    # Initiates report generation and returns a reference code that can be used
    # to fetch the completed report.
    #
    # @param query_id [String] Query ID from Client Portal
    # @param max_retries [Integer] Maximum number of retry attempts
    #
    # @return [String] Reference code for fetching the report
    #
    # @raise [FlexError::QueryNotFound] if query ID doesn't exist
    # @raise [FlexError::ConfigurationError] if token is invalid
    # @raise [FlexError::NetworkError] if network error occurs
    def generate_report(query_id, max_retries: MAX_RETRIES)
      validate_query_id!(query_id)

      response = http_client.get("/AccountManagement/FlexWebService/SendRequest", {
        t: token,
        q: query_id,
        v: FLEX_API_VERSION
      })

      handle_generate_response(response, query_id)
    rescue Faraday::Error => e
      handle_network_error(e, "generate report", query_id: query_id)
    end

    # Fetch a generated Flex report (Step 2 of 2)
    #
    # Retrieves a previously generated report using the reference code
    # returned by generate_report.
    #
    # @param reference_code [String] Reference code from generate_report
    # @param format [Symbol] Output format (:hash, :raw, :model)
    #   - :hash returns parsed data as Ruby hash
    #   - :raw returns unparsed XML string
    #   - :model returns FlexReport model instance
    #
    # @return [Hash, String, FlexReport] Report data in requested format
    #
    # @raise [FlexError::InvalidReference] if reference code is invalid
    # @raise [FlexError::ReportNotReady] if report is still generating
    # @raise [FlexError::NetworkError] if network error occurs
    def get_report(reference_code, format: :hash)
      validate_reference_code!(reference_code)

      response = http_client.get("/AccountManagement/FlexWebService/GetStatement", {
        t: token,
        q: reference_code,
        v: FLEX_API_VERSION
      })

      handle_get_response(response, reference_code, format)
    rescue Faraday::Error => e
      handle_network_error(e, "fetch report", reference_code: reference_code)
    end

    # Generate and fetch a report with automatic polling
    #
    # Combines generate_report and get_report with automatic retry logic
    # for reports that take time to generate.
    #
    # @param query_id [String] Query ID from Client Portal
    # @param max_wait [Integer] Maximum seconds to wait for report
    # @param poll_interval [Integer] Seconds between polling attempts
    #
    # @return [Hash] Parsed report data
    #
    # @raise [FlexError::ReportNotReady] if report not ready after max_wait
    # @raise [FlexError::InvalidReference] if reference expires while waiting
    def generate_and_fetch(query_id, max_wait: 60, poll_interval: RETRY_DELAY)
      reference_code = generate_report(query_id)

      start_time = Time.now
      while Time.now - start_time < max_wait
        begin
          report = get_report(reference_code)
          return report if report
        rescue FlexError::ReportNotReady
          sleep(poll_interval)
          next
        rescue FlexError::InvalidReference
          raise FlexError::InvalidReference.new(
            "Report reference expired while waiting",
            reference_code: reference_code,
            query_id: query_id
          )
        end
      end

      raise FlexError::ReportNotReady.new(
        "Report not ready after #{max_wait} seconds",
        reference_code: reference_code,
        query_id: query_id
      )
    end

    # Parse XML report data into structured hash
    #
    # @param xml_data [String, Hash] Raw XML string or pre-parsed hash
    #
    # @return [Hash] Structured report data with transactions, positions, etc.
    #
    # @raise [FlexError::ParseError] if XML parsing fails
    def parse_report(xml_data)
      return xml_data if xml_data.is_a?(Hash)

      begin
        parsed = FlexParser.parse(xml_data)
        extract_report_data(parsed)
      rescue => e
        raise FlexError::ParseError.new(
          "Failed to parse XML report: #{e.message}",
          xml_content: xml_data.to_s[0..500]
        )
      end
    end

    private

    def validate_configuration!
      if token.nil? || token.empty?
        raise FlexError::ConfigurationError.new(
          "Flex Web Service token not configured"
        )
      end
    end

    def validate_query_id!(query_id)
      if query_id.nil? || query_id.to_s.empty?
        raise ArgumentError, "Query ID is required"
      end
    end

    def validate_reference_code!(reference_code)
      if reference_code.nil? || reference_code.to_s.empty?
        raise ArgumentError, "Reference code is required"
      end
    end

    def fetch_token_from_credentials
      return nil unless defined?(::Rails)
      return nil unless ::Rails.respond_to?(:application)

      app = ::Rails.application
      return nil unless app.respond_to?(:credentials)

      app.credentials.dig(:ibkr, :flex, :token) ||
        app.credentials.dig(:ibkr, :flex_token)
    rescue
      nil
    end

    def http_client
      @http_client ||= Faraday.new(url: FLEX_BASE_URL) do |conn|
        conn.request :url_encoded
        conn.response :raise_error
        conn.adapter Faraday.default_adapter
        conn.options.timeout = config.timeout || 30
        conn.options.open_timeout = config.open_timeout || 10
      end
    end

    def handle_generate_response(response, query_id)
      return nil unless response.success?

      data = FlexParser.parse(response.body)

      if data[:FlexStatementResponse]
        statement_response = data[:FlexStatementResponse]

        # Handle both nested :value key and direct value
        status = statement_response[:Status]
        status = status[:value] if status.is_a?(Hash)

        if status == "Success"
          ref_code = statement_response[:ReferenceCode]
          ref_code = ref_code[:value] if ref_code.is_a?(Hash)
          ref_code&.strip
        else
          handle_flex_error(statement_response, query_id: query_id)
        end
      else
        raise FlexError::ParseError.new(
          "Unexpected response format",
          query_id: query_id,
          xml_content: response.body[0..500]
        )
      end
    end

    def handle_get_response(response, reference_code, format)
      return nil unless response.success?

      # Check if response is an error response
      parsed = FlexParser.parse(response.body)
      if parsed[:FlexStatementResponse]
        statement_response = parsed[:FlexStatementResponse]
        status = statement_response[:Status]
        status = status[:value] if status.is_a?(Hash)

        if status != "Success"
          handle_flex_error(statement_response, reference_code: reference_code)
        end
      end

      case format
      when :raw
        response.body
      when :hash
        parse_report(response.body)
      when :model
        data = parse_report(response.body)
        build_report_model(data, reference_code)
      else
        parse_report(response.body)
      end
    end

    def handle_flex_error(response_data, context = {})
      status = response_data[:Status]
      status[:value] if status.is_a?(Hash)

      error_code = response_data[:ErrorCode]
      error_code = error_code[:value] if error_code.is_a?(Hash)

      error_message = response_data[:ErrorMessage]
      error_message = error_message[:value] if error_message.is_a?(Hash)
      error_message ||= "Unknown error"

      case error_code.to_s
      when "1003", "1004"
        raise FlexError::QueryNotFound.new(
          "Query not found: #{error_message}",
          error_code: error_code,
          **context
        )
      when "1005", "1006"
        raise FlexError::InvalidReference.new(
          "Invalid reference: #{error_message}",
          error_code: error_code,
          **context
        )
      when "1007", "1008"
        raise FlexError::ConfigurationError.new(
          "Token error: #{error_message}",
          error_code: error_code,
          **context
        )
      when "1009", "1010"
        raise FlexError::ReportNotReady.new(
          "Report not ready: #{error_message}",
          error_code: error_code,
          retry_after: RETRY_DELAY,
          **context
        )
      when "1011"
        raise FlexError::RateLimitError.new(
          "Rate limit exceeded: #{error_message}",
          error_code: error_code,
          retry_after: 60,
          **context
        )
      else
        raise FlexError::ApiError.new(
          "Flex API error: #{error_message}",
          error_code: error_code,
          **context
        )
      end
    end

    def handle_network_error(error, operation, context = {})
      if error.response && error.response[:status] == 429
        raise FlexError::RateLimitError.new(
          "Rate limited while trying to #{operation}",
          **context
        )
      else
        raise FlexError::NetworkError.new(
          "Network error while trying to #{operation}: #{error.message}",
          **context
        )
      end
    end

    def extract_report_data(parsed_xml)
      return parsed_xml if parsed_xml.is_a?(Hash) && !parsed_xml[:FlexQueryResponse]

      if parsed_xml[:FlexQueryResponse]
        query_response = parsed_xml[:FlexQueryResponse]

        {
          query_name: query_response[:queryName],
          type: query_response[:type],
          accounts: extract_accounts(query_response),
          transactions: extract_transactions(query_response),
          positions: extract_positions(query_response),
          cash_report: extract_cash_report(query_response),
          performance: extract_performance(query_response)
        }.compact
      else
        parsed_xml
      end
    end

    def extract_accounts(query_response)
      return nil unless query_response[:FlexStatements]

      statement = query_response[:FlexStatements][:FlexStatement]
      return nil unless statement

      # Handle single statement or array of statements
      statements = statement.is_a?(Array) ? statement : [statement]
      statements.map { |s| s[:accountId] }.uniq.compact
    end

    def extract_transactions(query_response)
      return nil unless query_response[:FlexStatements]

      statement = query_response[:FlexStatements][:FlexStatement]
      return nil unless statement

      statements = statement.is_a?(Array) ? statement : [statement]
      transactions = []

      statements.each do |stmt|
        if stmt[:Trades] && stmt[:Trades][:Trade]
          trades = stmt[:Trades][:Trade]
          trades = trades.is_a?(Array) ? trades : [trades]
          transactions.concat(trades.map { |t| parse_transaction(t, stmt[:accountId]) })
        end
      end

      transactions.compact
    end

    def extract_positions(query_response)
      return nil unless query_response[:FlexStatements]

      statement = query_response[:FlexStatements][:FlexStatement]
      return nil unless statement

      statements = statement.is_a?(Array) ? statement : [statement]
      positions = []

      statements.each do |stmt|
        if stmt[:OpenPositions] && stmt[:OpenPositions][:OpenPosition]
          open_positions = stmt[:OpenPositions][:OpenPosition]
          open_positions = open_positions.is_a?(Array) ? open_positions : [open_positions]
          positions.concat(open_positions.map { |p| parse_position(p, stmt[:accountId]) })
        end
      end

      positions.compact
    end

    def extract_cash_report(query_response)
      return nil unless query_response[:FlexStatements]

      statement = query_response[:FlexStatements][:FlexStatement]
      return nil unless statement

      statements = statement.is_a?(Array) ? statement : [statement]
      cash_reports = []

      statements.each do |stmt|
        if stmt[:CashReport] && stmt[:CashReport][:CashReportCurrency]
          cash_data = stmt[:CashReport][:CashReportCurrency]
          cash_reports << parse_cash_report(cash_data, stmt[:accountId])
        end
      end

      cash_reports.compact
    end

    def extract_performance(query_response)
      return nil unless query_response[:FlexStatements]

      statement = query_response[:FlexStatements][:FlexStatement]
      return nil unless statement

      statements = statement.is_a?(Array) ? statement : [statement]
      performance_data = []

      statements.each do |stmt|
        if stmt[:Performance] && stmt[:Performance][:PerformanceSummary]
          perf = stmt[:Performance][:PerformanceSummary]
          performance_data << parse_performance(perf, stmt[:accountId])
        end
      end

      performance_data.compact
    end

    def parse_transaction(trade_data, account_id)
      {
        transaction_id: trade_data[:tradeID],
        account_id: account_id,
        symbol: trade_data[:symbol],
        trade_date: Date.parse(trade_data[:tradeDate]),
        settle_date: trade_data[:settlementDate] ? Date.parse(trade_data[:settlementDate]) : Date.parse(trade_data[:tradeDate]) + 2,
        quantity: trade_data[:quantity].to_f,
        price: trade_data[:tradePrice].to_f,
        proceeds: (trade_data[:quantity].to_f * trade_data[:tradePrice].to_f).round(2),
        commission: trade_data[:commission]&.to_f || 0,
        currency: trade_data[:currency] || "USD",
        asset_class: trade_data[:assetCategory]
      }
    rescue
      nil
    end

    def parse_position(position_data, account_id)
      {
        account_id: account_id,
        symbol: position_data[:symbol],
        position: position_data[:position].to_f,
        market_price: position_data[:markPrice].to_f,
        market_value: position_data[:position].to_f * position_data[:markPrice].to_f,
        average_cost: position_data[:costBasisPrice].to_f,
        unrealized_pnl: position_data[:fifoPnlUnrealized].to_f,
        realized_pnl: 0,
        currency: position_data[:currency] || "USD",
        asset_class: position_data[:assetCategory] || "STK"
      }
    rescue
      nil
    end

    def parse_cash_report(cash_data, account_id)
      {
        account_id: account_id,
        currency: cash_data[:currency],
        starting_cash: cash_data[:startingCash].to_f,
        ending_cash: cash_data[:endingCash].to_f,
        deposits: cash_data[:deposits].to_f,
        withdrawals: cash_data[:withdrawals].to_f
      }
    rescue
      nil
    end

    def parse_performance(perf_data, account_id)
      {
        account_id: account_id,
        period: perf_data[:reportDate],
        nav_start: perf_data[:netLiquidationValue].to_f,
        nav_end: perf_data[:netLiquidationValue].to_f,
        realized_pnl: perf_data[:total].to_f,
        unrealized_pnl: 0.0
      }
    rescue
      nil
    end

    def build_report_model(data, reference_code)
      Models::FlexReport.new(
        reference_code: reference_code,
        report_type: data[:type] || "unknown",
        generated_at: Time.now.to_i * 1000,
        account_id: data[:accounts]&.first,
        data: data
      )
    end
  end
end
