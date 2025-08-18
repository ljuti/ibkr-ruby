# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Flex do
  let(:token) { "test_flex_token_123" }
  let(:config) { instance_double(Ibkr::Configuration, flex_token: token, timeout: 30, open_timeout: 10) }
  let(:client) { instance_double(Ibkr::Client, config: config) }
  let(:flex_client) { described_class.new(token: token, config: config, client: client) }
  
  let(:query_id) { "123456" }
  let(:reference_code) { "2332907389" }
  
  let(:success_generate_response) do
    instance_double(Faraday::Response,
      success?: true,
      body: File.read(File.join(File.dirname(__FILE__), '../../fixtures/api_responses/flex/generate_success.xml'))
    )
  end
  
  let(:error_generate_response) do
    instance_double(Faraday::Response,
      success?: true,
      body: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<FlexStatementResponse><Status>Failed</Status><ErrorCode>1003</ErrorCode><ErrorMessage>Query not found</ErrorMessage></FlexStatementResponse>"
    )
  end
  
  let(:report_xml) do
    File.read(File.join(File.dirname(__FILE__), '../../fixtures/api_responses/flex/fetch_success.xml'))
  end

  describe "initialization" do
    context "when all parameters are provided" do
      it "initializes with explicit token" do
        flex = described_class.new(token: "explicit_token", config: config, client: client)
        expect(flex.token).to eq("explicit_token")
        expect(flex.config).to eq(config)
        expect(flex.client).to eq(client)
      end
    end

    context "when fetching token from config" do
      it "uses token from configuration" do
        flex = described_class.new(config: config)
        expect(flex.token).to eq(token)
      end
    end

    context "when using Rails credentials" do
      it "fetches token from Rails credentials" do
        rails_double = double("Rails")
        stub_const("Rails", rails_double)
        
        # Stub Rails.respond_to?(:application) to return true
        allow(rails_double).to receive(:respond_to?).with(:application).and_return(true)
        
        app_double = double("Rails::Application")
        allow(rails_double).to receive(:application).and_return(app_double)
        allow(app_double).to receive(:respond_to?).with(:credentials).and_return(true)
        allow(app_double).to receive(:credentials).and_return(double(dig: "rails_token"))
        
        flex = described_class.new(config: instance_double(Ibkr::Configuration, flex_token: nil, timeout: 30, open_timeout: 10))
        expect(flex.token).to eq("rails_token")
      end
    end

    context "when token is missing" do
      it "raises ConfigurationError" do
        # Ensure Rails constant doesn't interfere
        hide_const("Rails") if defined?(Rails)
        
        expect {
          described_class.new(token: nil, config: instance_double(Ibkr::Configuration, flex_token: nil, timeout: 30, open_timeout: 10))
        }.to raise_error(Ibkr::FlexError::ConfigurationError, /token not configured/)
      end
    end
  end

  describe "#generate_report" do
    let(:mock_http_client) { instance_double(Faraday::Connection) }

    before do
      allow(flex_client).to receive(:http_client).and_return(mock_http_client)
    end

    context "when generation succeeds" do
      it "returns reference code for successful request" do
        expect(mock_http_client).to receive(:get)
          .with("/AccountManagement/FlexWebService/SendRequest", hash_including(t: token, q: query_id, v: 3))
          .and_return(success_generate_response)

        result = flex_client.generate_report(query_id)
        expect(result).to eq(reference_code)
      end
    end

    context "when query is not found" do
      it "raises QueryNotFound error" do
        expect(mock_http_client).to receive(:get)
          .and_return(error_generate_response)

        expect {
          flex_client.generate_report(query_id)
        }.to raise_error(Ibkr::FlexError::QueryNotFound) do |error|
          expect(error.message).to include("Query not found")
          expect(error.error_code).to eq("1003")
          expect(error.query_id).to eq(query_id)
        end
      end
    end

    context "when network error occurs" do
      it "raises NetworkError" do
        expect(mock_http_client).to receive(:get)
          .and_raise(Faraday::ConnectionFailed.new("Connection timeout"))

        expect {
          flex_client.generate_report(query_id)
        }.to raise_error(Ibkr::FlexError::NetworkError) do |error|
          expect(error.message).to include("Network error")
          expect(error.message).to include("generate report")
        end
      end
    end

    context "when rate limited" do
      it "raises RateLimitError" do
        rate_limit_response = instance_double(Faraday::Response, status: 429)
        rate_limit_error = Faraday::ClientError.new("Rate limited", { status: 429, response: rate_limit_response })
        
        expect(mock_http_client).to receive(:get)
          .and_raise(rate_limit_error)

        expect {
          flex_client.generate_report(query_id)
        }.to raise_error(Ibkr::FlexError::RateLimitError) do |error|
          expect(error.message).to include("Rate limited")
          expect(error.retry_after).to be > 0
        end
      end
    end

    context "with invalid query_id" do
      it "raises ArgumentError for nil query_id" do
        expect {
          flex_client.generate_report(nil)
        }.to raise_error(ArgumentError, "Query ID is required")
      end

      it "raises ArgumentError for empty query_id" do
        expect {
          flex_client.generate_report("")
        }.to raise_error(ArgumentError, "Query ID is required")
      end
    end
  end

  describe "#get_report" do
    let(:mock_http_client) { instance_double(Faraday::Connection) }
    let(:success_report_response) do
      instance_double(Faraday::Response,
        success?: true,
        body: report_xml
      )
    end

    before do
      allow(flex_client).to receive(:http_client).and_return(mock_http_client)
    end

    context "when fetching report succeeds" do
      it "returns parsed report data as hash" do
        expect(mock_http_client).to receive(:get)
          .with("/AccountManagement/FlexWebService/GetStatement", hash_including(t: token, q: reference_code))
          .and_return(success_report_response)

        result = flex_client.get_report(reference_code)
        
        expect(result).to be_a(Hash)
        expect(result[:query_name]).to eq("Test Report")
        expect(result[:type]).to eq("AF")
        expect(result[:accounts]).to include("DU123456")
        expect(result[:transactions]).to be_an(Array)
        expect(result[:positions]).to be_an(Array)
      end

      it "returns raw XML when format is :raw" do
        expect(mock_http_client).to receive(:get)
          .and_return(success_report_response)

        result = flex_client.get_report(reference_code, format: :raw)
        expect(result).to eq(report_xml)
      end

      it "returns model when format is :model" do
        expect(mock_http_client).to receive(:get)
          .and_return(success_report_response)

        result = flex_client.get_report(reference_code, format: :model)
        expect(result).to be_a(Ibkr::Models::FlexReport)
        expect(result.reference_code).to eq(reference_code)
        expect(result.report_type).to eq("AF")
      end
    end

    context "when report is not ready" do
      let(:not_ready_response) do
        instance_double(Faraday::Response,
          success?: true,
          body: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<FlexStatementResponse><Status>InProgress</Status><ErrorCode>1009</ErrorCode><ErrorMessage>Report not ready</ErrorMessage></FlexStatementResponse>"
        )
      end

      it "raises ReportNotReady error" do
        allow(mock_http_client).to receive(:get).and_return(not_ready_response)
        allow(flex_client).to receive(:parse_report).and_call_original

        expect {
          flex_client.get_report(reference_code)
        }.to raise_error(Ibkr::FlexError::ReportNotReady) do |error|
          expect(error.retryable?).to be true
          expect(error.retry_after).to eq(5)
        end
      end
    end

    context "with invalid reference_code" do
      it "raises ArgumentError for nil reference_code" do
        expect {
          flex_client.get_report(nil)
        }.to raise_error(ArgumentError, "Reference code is required")
      end

      it "raises ArgumentError for empty reference_code" do
        expect {
          flex_client.get_report("")
        }.to raise_error(ArgumentError, "Reference code is required")
      end
    end
  end

  describe "#generate_and_fetch" do
    let(:mock_http_client) { instance_double(Faraday::Connection) }

    before do
      allow(flex_client).to receive(:http_client).and_return(mock_http_client)
    end

    context "when report is ready immediately" do
      it "returns the report data" do
        expect(flex_client).to receive(:generate_report).with(query_id).and_return(reference_code)
        expect(flex_client).to receive(:get_report).with(reference_code).and_return({ data: "test" })

        result = flex_client.generate_and_fetch(query_id)
        expect(result).to eq({ data: "test" })
      end
    end

    context "when report needs polling" do
      it "retries until report is ready" do
        expect(flex_client).to receive(:generate_report).with(query_id).and_return(reference_code)
        
        call_count = 0
        expect(flex_client).to receive(:get_report).exactly(3).times do
          call_count += 1
          if call_count < 3
            raise Ibkr::FlexError::ReportNotReady.new("Not ready")
          else
            { data: "test" }
          end
        end

        allow(flex_client).to receive(:sleep)

        result = flex_client.generate_and_fetch(query_id, poll_interval: 0.1)
        expect(result).to eq({ data: "test" })
      end
    end

    context "when report times out" do
      it "raises ReportNotReady after max_wait" do
        expect(flex_client).to receive(:generate_report).with(query_id).and_return(reference_code)
        expect(flex_client).to receive(:get_report).at_least(:once).and_raise(Ibkr::FlexError::ReportNotReady.new("Not ready"))
        allow(flex_client).to receive(:sleep)

        expect {
          flex_client.generate_and_fetch(query_id, max_wait: 0.1, poll_interval: 0.05)
        }.to raise_error(Ibkr::FlexError::ReportNotReady) do |error|
          expect(error.message).to include("not ready after")
        end
      end
    end

    context "when reference expires during polling" do
      it "raises InvalidReference error" do
        expect(flex_client).to receive(:generate_report).with(query_id).and_return(reference_code)
        expect(flex_client).to receive(:get_report).and_raise(Ibkr::FlexError::InvalidReference.new("Expired"))

        expect {
          flex_client.generate_and_fetch(query_id)
        }.to raise_error(Ibkr::FlexError::InvalidReference) do |error|
          expect(error.message).to include("expired while waiting")
        end
      end
    end
  end

  describe "#parse_report" do
    context "with valid XML" do
      it "extracts transactions correctly" do
        result = flex_client.parse_report(report_xml)
        
        expect(result[:transactions]).to be_an(Array)
        expect(result[:transactions].first).to include(
          transaction_id: "987654321",
          symbol: "AAPL",
          quantity: 100.0,
          price: 150.5,
          currency: "USD"
        )
      end

      it "extracts positions correctly" do
        result = flex_client.parse_report(report_xml)
        
        expect(result[:positions]).to be_an(Array)
        position = result[:positions].first
        expect(position).to include(
          symbol: "AAPL",
          position: 100.0,
          market_price: 155.0,
          unrealized_pnl: 450.0
        )
      end

      it "extracts account information" do
        result = flex_client.parse_report(report_xml)
        
        expect(result[:accounts]).to include("DU123456")
      end
    end

    context "with malformed XML" do
      it "raises ParseError" do
        expect {
          flex_client.parse_report("invalid xml <")
        }.to raise_error(Ibkr::FlexError::ParseError) do |error|
          expect(error.message).to include("Failed to parse XML")
          expect(error.xml_content).to include("invalid xml")
        end
      end
    end

    context "with already parsed hash" do
      it "returns the hash unchanged" do
        input = { already: "parsed" }
        result = flex_client.parse_report(input)
        expect(result).to eq(input)
      end
    end
  end

  describe "error handling" do
    let(:mock_http_client) { instance_double(Faraday::Connection) }

    before do
      allow(flex_client).to receive(:http_client).and_return(mock_http_client)
    end

    it "provides comprehensive error context" do
      allow(mock_http_client).to receive(:get).and_return(error_generate_response)

      begin
        flex_client.generate_report(query_id)
      rescue Ibkr::FlexError::QueryNotFound => e
        error_hash = e.to_h
        expect(error_hash[:error]).to eq("Ibkr::FlexError::QueryNotFound")
        expect(error_hash[:message]).to include("Query not found")
        expect(error_hash[:suggestions]).to be_an(Array)
        expect(error_hash[:suggestions]).to include(/Verify query ID exists/)
        expect(error_hash[:error_code]).to eq("1003")
        expect(error_hash[:query_id]).to eq(query_id)
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent report generation" do
      mock_http_client = instance_double(Faraday::Connection)
      allow(flex_client).to receive(:http_client).and_return(mock_http_client)
      allow(mock_http_client).to receive(:get).and_return(success_generate_response)

      threads = 5.times.map do |i|
        Thread.new do
          flex_client.generate_report("query_#{i}")
        end
      end

      results = threads.map(&:join).map(&:value)
      expect(results).to all(eq(reference_code))
    end
  end
end