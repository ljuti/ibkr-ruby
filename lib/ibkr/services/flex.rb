# frozen_string_literal: true

require_relative "base"
require_relative "../flex"

module Ibkr
  module Services
    # Service layer for Flex Web Service operations
    #
    # Provides high-level methods for generating and retrieving Flex reports
    # with automatic type conversion to data models.
    #
    # @example Get transactions
    #   client = Ibkr::Client.new(default_account_id: "DU123456")
    #   transactions = client.flex.transactions_report("123456")
    #   transactions.each { |tx| puts "#{tx.symbol}: #{tx.net_amount}" }
    #
    class Flex < Base
      # Initialize Flex service
      #
      # @param client [Ibkr::Client] Parent client instance
      # @param token [String, nil] Optional Flex token override
      def initialize(client, token: nil)
        super(client)
        @flex_client = Ibkr::Flex.new(
          token: token,
          config: client.config,
          client: client
        )
      end

      # Generate a Flex report
      #
      # @param query_id [String] Query ID from Client Portal
      # @return [String] Reference code for fetching report
      def generate_report(query_id)
        @flex_client.generate_report(query_id)
      end

      # Fetch a generated report
      #
      # @param reference_code [String] Reference from generate_report
      # @param format [Symbol] Output format (:hash, :raw, :model)
      # @return [Hash, String, FlexReport] Report in requested format
      def get_report(reference_code, format: :hash)
        @flex_client.get_report(reference_code, format: format)
      end

      # Generate and fetch report with polling
      #
      # @param query_id [String] Query ID from Client Portal
      # @param max_wait [Integer] Maximum seconds to wait
      # @param poll_interval [Integer] Seconds between polls
      # @return [Hash] Parsed report data
      def generate_and_fetch(query_id, max_wait: 60, poll_interval: 5)
        @flex_client.generate_and_fetch(
          query_id,
          max_wait: max_wait,
          poll_interval: poll_interval
        )
      end

      # Get transactions as FlexTransaction models
      #
      # @param query_id [String] Query ID from Client Portal
      # @param max_wait [Integer] Maximum seconds to wait
      # @return [Array<FlexTransaction>] Array of transaction models
      def transactions_report(query_id, max_wait: 60)
        report_data = generate_and_fetch(query_id, max_wait: max_wait)
        
        return [] unless report_data && report_data[:transactions]
        
        report_data[:transactions].map do |txn_data|
          Models::FlexTransaction.new(txn_data)
        end
      end

      # Get positions as FlexPosition models
      #
      # @param query_id [String] Query ID from Client Portal
      # @param max_wait [Integer] Maximum seconds to wait
      # @return [Array<FlexPosition>] Array of position models
      def positions_report(query_id, max_wait: 60)
        report_data = generate_and_fetch(query_id, max_wait: max_wait)
        
        return [] unless report_data && report_data[:positions]
        
        report_data[:positions].map do |pos_data|
          Models::FlexPosition.new(pos_data)
        end
      end

      # Get cash report as FlexCashReport model
      #
      # @param query_id [String] Query ID from Client Portal
      # @param max_wait [Integer] Maximum seconds to wait
      # @return [FlexCashReport, nil] Cash report model or nil if not available
      def cash_report(query_id, max_wait: 60)
        report_data = generate_and_fetch(query_id, max_wait: max_wait)
        
        return nil unless report_data && report_data[:cash_report]
        
        cash_data = report_data[:cash_report].first
        Models::FlexCashReport.new(cash_data) if cash_data
      end

      # Get performance report as FlexPerformance model
      #
      # @param query_id [String] Query ID from Client Portal
      # @param max_wait [Integer] Maximum seconds to wait
      # @return [FlexPerformance, nil] Performance model or nil if not available
      def performance_report(query_id, max_wait: 60)
        report_data = generate_and_fetch(query_id, max_wait: max_wait)
        
        return nil unless report_data && report_data[:performance]
        
        perf_data = report_data[:performance].first
        Models::FlexPerformance.new(perf_data) if perf_data
      end

      # Check if Flex service is available
      #
      # @return [Boolean] true if token is configured
      def available?
        !@flex_client.token.nil?
      rescue StandardError
        false
      end

      private

      attr_reader :flex_client
    end
  end
end