# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Flex-specific error handling" do
  describe Ibkr::FlexError::Base do
    it "inherits from Ibkr::BaseError" do
      expect(described_class.ancestors).to include(Ibkr::BaseError)
    end

    it "stores error context" do
      error = described_class.new("Test error",
        error_code: "TEST001",
        query_id: "123456",
        reference_code: "REF789")

      expect(error.error_code).to eq("TEST001")
      expect(error.query_id).to eq("123456")
      expect(error.reference_code).to eq("REF789")
    end

    it "provides suggestions" do
      error = described_class.new("Test error")
      expect(error.suggestions).to be_an(Array)
      expect(error.suggestions).not_to be_empty
    end
  end

  describe Ibkr::FlexError::ConfigurationError do
    it "provides configuration-specific suggestions" do
      error = described_class.new("Token missing")

      expect(error.suggestions).to be_an(Array)
      expect(error.suggestions.any? { |s| s.include?("token") }).to be true
    end
  end

  describe Ibkr::FlexError::QueryNotFound do
    it "stores query context" do
      error = described_class.new("Query not found",
        error_code: "1003",
        query_id: "999999")

      expect(error.error_code).to eq("1003")
      expect(error.query_id).to eq("999999")
    end

    it "provides query-specific suggestions" do
      error = described_class.new("Query not found")
      expect(error.suggestions.any? { |s| s.include?("query") || s.include?("Query") }).to be true
    end
  end

  describe Ibkr::FlexError::ReportNotReady do
    it "indicates retry is possible" do
      error = described_class.new("Report generating",
        error_code: "1009",
        reference_code: "REF123")

      expect(error).to respond_to(:retryable?)
      expect(error.retryable?).to be true
    end

    it "provides retry suggestions" do
      error = described_class.new("Not ready")
      expect(error.suggestions.any? { |s| s.downcase.include?("retry") || s.include?("wait") }).to be true
    end
  end

  describe Ibkr::FlexError::InvalidReference do
    it "stores reference context" do
      error = described_class.new("Invalid reference",
        error_code: "1005",
        reference_code: "EXPIRED123")

      expect(error.error_code).to eq("1005")
      expect(error.reference_code).to eq("EXPIRED123")
    end
  end

  describe Ibkr::FlexError::NetworkError do
    it "handles network failures" do
      error = described_class.new("Connection timeout",
        context: {endpoint: "/flex/api"})

      expect(error.message).to eq("Connection timeout")
      expect(error.to_h[:context][:endpoint]).to eq("/flex/api")
    end

    it "provides network troubleshooting suggestions" do
      error = described_class.new("Network error")
      expect(error.suggestions.any? { |s| s.downcase.include?("network") || s.include?("connectivity") }).to be true
    end
  end

  describe Ibkr::FlexError::ParseError do
    it "handles XML parsing failures" do
      error = described_class.new("Invalid XML",
        context: {xml_content: "<invalid>"})

      expect(error.message).to eq("Invalid XML")
      expect(error.to_h[:context][:xml_content]).to eq("<invalid>")
    end

    it "provides parsing suggestions" do
      error = described_class.new("Parse error")
      expect(error.suggestions).to be_an(Array)
      expect(error.suggestions).not_to be_empty
    end
  end

  describe Ibkr::FlexError::RateLimitError do
    it "indicates retry with delay" do
      error = described_class.new("Rate limited",
        error_code: "1011",
        retry_after: 60)

      expect(error).to respond_to(:retryable?)
      expect(error.retryable?).to be true
      expect(error.retry_after).to eq(60)
    end
  end

  describe Ibkr::FlexError::ApiError do
    it "handles general API errors" do
      error = described_class.new("API error",
        error_code: "2001",
        context: {response_code: 500})

      expect(error.error_code).to eq("2001")
      expect(error.to_h[:context][:response_code]).to eq(500)
    end
  end
end
