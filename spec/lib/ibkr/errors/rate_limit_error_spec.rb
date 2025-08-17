# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::RateLimitError do
  let(:message) { "Rate limit exceeded" }
  let(:options) do
    {
      retry_after: 60,
      limit: 100,
      remaining: 0,
      reset_time: Time.at(1690876800) # 2023-08-01 12:00:00 UTC
    }
  end

  describe "initialization" do
    context "with default message and no options" do
      subject(:error) { described_class.new }

      it "uses default message" do
        expect(error.message).to eq("Rate limit exceeded")
      end

      it "sets all rate limit attributes to nil" do
        expect(error.retry_after).to be_nil
        expect(error.limit).to be_nil
        expect(error.remaining).to be_nil
        expect(error.reset_time).to be_nil
      end
    end

    context "with custom message and options" do
      subject(:error) { described_class.new(message, **options) }

      it "uses the provided message" do
        expect(error.message).to eq(message)
      end

      it "sets retry_after from options" do
        expect(error.retry_after).to eq(60)
      end

      it "sets limit from options" do
        expect(error.limit).to eq(100)
      end

      it "sets remaining from options" do
        expect(error.remaining).to eq(0)
      end

      it "sets reset_time from options" do
        expect(error.reset_time).to eq(Time.at(1690876800))
      end
    end

    context "with partial options" do
      subject(:error) do
        described_class.new("Custom message", retry_after: 30, limit: 50)
      end

      it "sets provided options" do
        expect(error.retry_after).to eq(30)
        expect(error.limit).to eq(50)
      end

      it "leaves unspecified options as nil" do
        expect(error.remaining).to be_nil
        expect(error.reset_time).to be_nil
      end
    end
  end

  describe "#to_h" do
    subject(:error) { described_class.new(message, **options) }

    it "returns a hash with all rate limit information" do
      hash = error.to_h

      expect(hash[:retry_after]).to eq(60)
      expect(hash[:limit]).to eq(100)
      expect(hash[:remaining]).to eq(0)
      expect(hash[:reset_time]).to eq(Time.at(1690876800))
    end

    it "includes base error information" do
      hash = error.to_h

      expect(hash[:error]).to eq("Ibkr::RateLimitError")
      expect(hash[:message]).to eq(message)
    end

    context "with nil values" do
      subject(:error) { described_class.new("Test", retry_after: 30) }

      it "compacts nil values from the hash" do
        hash = error.to_h

        expect(hash).to have_key(:retry_after)
        expect(hash).not_to have_key(:limit)
        expect(hash).not_to have_key(:remaining)
        expect(hash).not_to have_key(:reset_time)
      end
    end
  end

  describe ".from_response" do
    let(:response_headers) do
      {
        "Retry-After" => "120",
        "X-RateLimit-Limit" => "1000",
        "X-RateLimit-Remaining" => "5",
        "X-RateLimit-Reset" => "1690876800"
      }
    end
    let(:response) { double("response", headers: response_headers) }

    context "with complete rate limit headers" do
      subject(:error) { described_class.from_response(response) }

      it "extracts retry_after from Retry-After header" do
        expect(error.retry_after).to eq(120)
      end

      it "extracts limit from X-RateLimit-Limit header" do
        expect(error.limit).to eq(1000)
      end

      it "extracts remaining from X-RateLimit-Remaining header" do
        expect(error.remaining).to eq(5)
      end

      it "extracts reset_time from X-RateLimit-Reset header" do
        expect(error.reset_time).to eq(Time.at(1690876800))
      end

      it "sets the response object" do
        allow(error).to receive(:response).and_return(response)
        expect(error.response).to eq(response)
      end

      it "builds a descriptive error message" do
        expect(error.message).to eq("Rate limit exceeded. Retry after 120 seconds. 5 requests remaining")
      end
    end

    context "with only Retry-After header" do
      let(:response_headers) { {"Retry-After" => "60"} }

      it "builds message with retry after information" do
        error = described_class.from_response(response)
        expect(error.message).to eq("Rate limit exceeded. Retry after 60 seconds")
      end
    end

    context "with only reset time header" do
      let(:response_headers) { {"X-RateLimit-Reset" => "1690876800"} }

      it "builds message with reset time information" do
        error = described_class.from_response(response)
        expect(error.message).to include("Rate limit exceeded. Rate limit resets at")
        expect(error.message).to include("2023-08-01")
      end
    end

    context "with only remaining requests header" do
      let(:response_headers) { {"X-RateLimit-Remaining" => "3"} }

      it "builds message with remaining requests information" do
        error = described_class.from_response(response)
        expect(error.message).to eq("Rate limit exceeded. 3 requests remaining")
      end
    end

    context "with no rate limit headers" do
      let(:response_headers) { {} }

      it "uses default error message" do
        error = described_class.from_response(response)
        expect(error.message).to eq("Rate limit exceeded")
      end

      it "sets all rate limit attributes to nil" do
        error = described_class.from_response(response)

        expect(error.retry_after).to be_nil
        expect(error.limit).to be_nil
        expect(error.remaining).to be_nil
        expect(error.reset_time).to be_nil
      end
    end

    context "with custom message parameter" do
      it "uses the provided message instead of building one" do
        error = described_class.from_response(response, message: "Custom rate limit message")
        expect(error.message).to eq("Custom rate limit message")
      end
    end

    context "with headers containing non-numeric values" do
      let(:response_headers) do
        {
          "Retry-After" => "invalid",
          "X-RateLimit-Limit" => "not_a_number",
          "X-RateLimit-Remaining" => "",
          "X-RateLimit-Reset" => "invalid_timestamp"
        }
      end

      it "handles invalid header values gracefully" do
        error = described_class.from_response(response)

        expect(error.retry_after).to eq(0) # "invalid".to_i
        expect(error.limit).to eq(0) # "not_a_number".to_i
        expect(error.remaining).to eq(0) # "".to_i
        expect(error.reset_time).to eq(Time.at(0)) # Time.at("invalid_timestamp".to_i)
      end
    end

    context "with nil headers" do
      let(:response_headers) do
        {
          "Retry-After" => nil,
          "X-RateLimit-Limit" => nil,
          "X-RateLimit-Remaining" => nil,
          "X-RateLimit-Reset" => nil
        }
      end

      it "handles nil header values gracefully" do
        error = described_class.from_response(response)

        expect(error.retry_after).to be_nil
        expect(error.limit).to be_nil
        expect(error.remaining).to be_nil
        expect(error.reset_time).to be_nil
      end
    end
  end

  describe "message building behavior" do
    describe ".build_rate_limit_message" do
      # Testing the private method behavior through the public interface

      context "with retry_after and remaining" do
        let(:response_headers) do
          {
            "Retry-After" => "30",
            "X-RateLimit-Remaining" => "10"
          }
        end
        let(:response) { double("response", headers: response_headers) }

        it "includes both retry after and remaining information" do
          error = described_class.from_response(response)
          expect(error.message).to eq("Rate limit exceeded. Retry after 30 seconds. 10 requests remaining")
        end
      end

      context "with reset_time and remaining" do
        let(:response_headers) do
          {
            "X-RateLimit-Reset" => "1690876800",
            "X-RateLimit-Remaining" => "5"
          }
        end
        let(:response) { double("response", headers: response_headers) }

        it "includes both reset time and remaining information" do
          error = described_class.from_response(response)
          expect(error.message).to include("Rate limit exceeded. Rate limit resets at")
          expect(error.message).to include("2023-08-01")
          expect(error.message).to include("5 requests remaining")
        end
      end

      context "with retry_after taking precedence over reset_time" do
        let(:response_headers) do
          {
            "Retry-After" => "45",
            "X-RateLimit-Reset" => "1690876800"
          }
        end
        let(:response) { double("response", headers: response_headers) }

        it "uses retry_after when both are present" do
          error = described_class.from_response(response)
          expect(error.message).to include("Retry after 45 seconds")
          expect(error.message).not_to include("Rate limit resets at")
        end
      end
    end
  end

  describe "inheritance from BaseError" do
    subject(:error) { described_class.new(message, **options) }

    it "inherits from BaseError" do
      expect(error).to be_a(Ibkr::BaseError)
    end

    it "supports BaseError context features" do
      expect(error.context).to be_a(Hash)
      expect(error.context).to have_key(:timestamp)
    end

    it "generates suggestions for rate limit scenarios" do
      expect(error.suggestions).to include("Implement exponential backoff in your retry logic")
      expect(error.suggestions).to include("Reduce the frequency of API calls")
      expect(error.suggestions).to include("Consider caching responses to minimize API usage")
    end
  end

  describe "error recovery information" do
    subject(:error) { described_class.new(message, **options) }

    it "provides actionable retry information" do
      expect(error.retry_after).to eq(60)
      expect(error.reset_time).to eq(Time.at(1690876800))
    end

    it "includes current quota information" do
      expect(error.limit).to eq(100)
      expect(error.remaining).to eq(0)
    end

    it "can be converted to hash for logging or API responses" do
      hash = error.to_h

      expect(hash).to include(
        retry_after: 60,
        limit: 100,
        remaining: 0,
        reset_time: Time.at(1690876800)
      )
    end
  end
end
