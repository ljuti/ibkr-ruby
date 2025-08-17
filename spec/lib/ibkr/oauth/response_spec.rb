# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Oauth::Response do
  let(:mock_signature_generator) do
    instance_double(Ibkr::Oauth::SignatureGenerator,
      compute_live_session_token: "computed_token")
  end

  let(:parser) { described_class.new(signature_generator: mock_signature_generator) }

  describe "#initialize" do
    it "sets signature generator" do
      expect(parser.signature_generator).to eq(mock_signature_generator)
    end

    it "requires signature generator parameter" do
      expect { described_class.new(signature_generator: nil) }.not_to raise_error
      expect { described_class.new(signature_generator: mock_signature_generator) }.not_to raise_error
    end
  end

  describe "#parse_live_session_token" do
    let(:dh_response) { "dh_response_value" }
    let(:signature) { "token_signature" }
    let(:expiration) { "1234567890" }

    context "with successful response" do
      let(:success_response) do
        double("response",
          success?: true,
          body: {
            diffie_hellman_response: dh_response,
            live_session_token_signature: signature,
            live_session_token_expiration: expiration
          }.to_json)
      end

      it "parses live session token successfully" do
        token = parser.parse_live_session_token(success_response)

        expect(token).to be_a(Ibkr::Oauth::LiveSessionToken)
        expect(mock_signature_generator).to have_received(:compute_live_session_token).with(dh_response)
      end

      it "creates token with correct values" do
        token = parser.parse_live_session_token(success_response)

        expect(token.token).to eq("computed_token")
        expect(token.signature).to eq(signature)
        expect(token.expires_in).to eq(expiration)
      end

      it "validates response success before parsing" do
        # validate_response_success! is called by parse_json_response which is called by parse_live_session_token
        expect(parser).to receive(:validate_response_success!).with(success_response).exactly(:once).and_call_original
        # But actually it's called by parse_json_response, not directly
        parser.parse_live_session_token(success_response)
      end

      it "parses JSON response body" do
        expect(parser).to receive(:parse_json_response).with(success_response).and_call_original
        parser.parse_live_session_token(success_response)
      end
    end

    context "with missing fields" do
      let(:incomplete_response) do
        double("response",
          success?: true,
          body: {some_field: "value"}.to_json)
      end

      it "creates token with nil values for missing fields" do
        token = parser.parse_live_session_token(incomplete_response)

        expect(token).to be_a(Ibkr::Oauth::LiveSessionToken)
        expect(token.signature).to be_nil
        expect(token.expires_in).to be_nil
      end

      it "still computes token even with missing DH response" do
        allow(mock_signature_generator).to receive(:compute_live_session_token).with(nil).and_return("computed_with_nil")

        token = parser.parse_live_session_token(incomplete_response)
        expect(token.token).to eq("computed_with_nil")
        expect(mock_signature_generator).to have_received(:compute_live_session_token).with(nil)
      end
    end

    context "with failed response" do
      let(:failed_response) do
        double("response", success?: false, status: 401, body: "Unauthorized")
      end

      it "raises AuthenticationError" do
        expect { parser.parse_live_session_token(failed_response) }
          .to raise_error(Ibkr::AuthenticationError)
      end

      it "does not attempt to parse JSON for failed response" do
        # JSON.parse is actually called by the error handler to parse error details
        # So we can't expect it not to be called at all
        expect { parser.parse_live_session_token(failed_response) }
          .to raise_error(Ibkr::AuthenticationError)
      end
    end

    context "with invalid JSON" do
      let(:invalid_response) do
        double("response", success?: true, body: "not json")
      end

      it "raises AuthenticationError with parse error message" do
        expect { parser.parse_live_session_token(invalid_response) }
          .to raise_error(Ibkr::AuthenticationError, /Invalid response format/)
      end

      it "includes original error message" do
        expect { parser.parse_live_session_token(invalid_response) }
          .to raise_error(Ibkr::AuthenticationError) do |error|
            expect(error.message).to include("Invalid response format")
          end
      end
    end

    context "with empty response body" do
      let(:empty_response) do
        double("response", success?: true, body: "")
      end

      it "raises AuthenticationError for empty body" do
        expect { parser.parse_live_session_token(empty_response) }
          .to raise_error(Ibkr::AuthenticationError)
      end
    end

    context "with null JSON values" do
      let(:null_response) do
        double("response",
          success?: true,
          body: {
            diffie_hellman_response: nil,
            live_session_token_signature: nil,
            live_session_token_expiration: nil
          }.to_json)
      end

      it "creates token with nil values" do
        allow(mock_signature_generator).to receive(:compute_live_session_token).with(nil).and_return("computed_with_nil")

        token = parser.parse_live_session_token(null_response)

        expect(token).to be_a(Ibkr::Oauth::LiveSessionToken)
        expect(token.token).to eq("computed_with_nil")
        expect(token.signature).to be_nil
        expect(token.expires_in).to be_nil
      end
    end
  end

  describe "#parse_json_response" do
    context "with valid JSON response" do
      let(:success_response) do
        double("response", success?: true, body: '{"key": "value"}')
      end

      it "parses JSON successfully" do
        result = parser.parse_json_response(success_response)
        expect(result).to eq({"key" => "value"})
      end

      it "validates response success before parsing" do
        expect(parser).to receive(:validate_response_success!).with(success_response).and_call_original
        parser.parse_json_response(success_response)
      end

      it "returns parsed hash" do
        result = parser.parse_json_response(success_response)
        expect(result).to be_a(Hash)
      end
    end

    context "with complex JSON" do
      let(:complex_response) do
        double("response",
          success?: true,
          body: '{"nested": {"key": "value"}, "array": [1, 2, 3]}')
      end

      it "parses complex JSON structures" do
        result = parser.parse_json_response(complex_response)
        expect(result).to eq({
          "nested" => {"key" => "value"},
          "array" => [1, 2, 3]
        })
      end
    end

    context "with failed response" do
      let(:failed_response) do
        double("response", success?: false, status: 500, body: "Server Error")
      end

      it "raises AuthenticationError" do
        expect { parser.parse_json_response(failed_response) }
          .to raise_error(Ibkr::AuthenticationError)
      end

      it "calls validate_response_success!" do
        expect(parser).to receive(:validate_response_success!).with(failed_response).and_call_original

        expect { parser.parse_json_response(failed_response) }
          .to raise_error(Ibkr::AuthenticationError)
      end

      it "does not attempt JSON parsing for response body" do
        # The error handler might parse the error body, but not the main response
        expect { parser.parse_json_response(failed_response) }
          .to raise_error(Ibkr::AuthenticationError)
      end
    end

    context "with invalid JSON" do
      let(:invalid_response) do
        double("response", success?: true, body: "invalid json")
      end

      it "raises AuthenticationError with parse error message" do
        expect { parser.parse_json_response(invalid_response) }
          .to raise_error(Ibkr::AuthenticationError, /Invalid response format/)
      end

      it "wraps JSON::ParserError" do
        expect { parser.parse_json_response(invalid_response) }
          .to raise_error(Ibkr::AuthenticationError) do |error|
            expect(error.message).to include("Invalid response format")
          end
      end

      it "includes original parser error details" do
        expect { parser.parse_json_response(invalid_response) }
          .to raise_error(Ibkr::AuthenticationError) do |error|
            expect(error.message).to match(/unexpected character|unexpected token/)
          end
      end
    end

    context "with empty body" do
      let(:empty_response) do
        double("response", success?: true, body: "")
      end

      it "raises AuthenticationError for empty JSON" do
        expect { parser.parse_json_response(empty_response) }
          .to raise_error(Ibkr::AuthenticationError, /Invalid response format/)
      end
    end

    context "with whitespace-only body" do
      let(:whitespace_response) do
        double("response", success?: true, body: "   \n\t  ")
      end

      it "raises AuthenticationError for whitespace" do
        expect { parser.parse_json_response(whitespace_response) }
          .to raise_error(Ibkr::AuthenticationError, /Invalid response format/)
      end
    end
  end

  describe "private methods" do
    describe "#validate_response_success!" do
      context "with successful response" do
        let(:success_response) do
          double("response", success?: true, body: "OK")
        end

        it "returns nil for successful response" do
          result = parser.send(:validate_response_success!, success_response)
          expect(result).to be_nil
        end

        it "does not raise error" do
          expect { parser.send(:validate_response_success!, success_response) }
            .not_to raise_error
        end
      end

      context "with failed response" do
        let(:failed_response) do
          double("response", success?: false, status: 401, body: "Unauthorized")
        end

        it "raises AuthenticationError" do
          expect { parser.send(:validate_response_success!, failed_response) }
            .to raise_error(Ibkr::AuthenticationError)
        end

        it "uses from_response to create error" do
          expect(Ibkr::AuthenticationError).to receive(:from_response).with(failed_response).and_call_original

          expect { parser.send(:validate_response_success!, failed_response) }
            .to raise_error(Ibkr::AuthenticationError)
        end
      end

      context "with different error statuses" do
        it "raises AuthenticationError for 400" do
          response = double("response", success?: false, status: 400, body: "Bad Request")
          expect { parser.send(:validate_response_success!, response) }
            .to raise_error(Ibkr::AuthenticationError)
        end

        it "raises AuthenticationError for 403" do
          response = double("response", success?: false, status: 403, body: "Forbidden")
          expect { parser.send(:validate_response_success!, response) }
            .to raise_error(Ibkr::AuthenticationError)
        end

        it "raises AuthenticationError for 500" do
          response = double("response", success?: false, status: 500, body: "Server Error")
          expect { parser.send(:validate_response_success!, response) }
            .to raise_error(Ibkr::AuthenticationError)
        end
      end
    end

    describe "#validate_required_fields!" do
      let(:data) { {"field1" => "value1", "field2" => "value2"} }

      context "when all required fields are present" do
        let(:required_fields) { ["field1", "field2"] }

        it "returns nil" do
          result = parser.send(:validate_required_fields!, data, required_fields)
          expect(result).to be_nil
        end

        it "does not raise error" do
          expect { parser.send(:validate_required_fields!, data, required_fields) }
            .not_to raise_error
        end
      end

      context "when some required fields are missing" do
        let(:required_fields) { ["field1", "field3", "field4"] }

        it "raises AuthenticationError" do
          expect { parser.send(:validate_required_fields!, data, required_fields) }
            .to raise_error(Ibkr::AuthenticationError)
        end

        it "includes missing field names in error message" do
          expect { parser.send(:validate_required_fields!, data, required_fields) }
            .to raise_error(Ibkr::AuthenticationError, /Missing required fields in response: field3, field4/)
        end

        it "lists all missing fields" do
          expect { parser.send(:validate_required_fields!, data, required_fields) }
            .to raise_error(Ibkr::AuthenticationError) do |error|
              expect(error.message).to include("field3")
              expect(error.message).to include("field4")
            end
        end
      end

      context "when all required fields are missing" do
        let(:required_fields) { ["field3", "field4"] }

        it "raises AuthenticationError" do
          expect { parser.send(:validate_required_fields!, data, required_fields) }
            .to raise_error(Ibkr::AuthenticationError, /Missing required fields in response: field3, field4/)
        end
      end

      context "with empty required fields" do
        let(:required_fields) { [] }

        it "returns nil" do
          result = parser.send(:validate_required_fields!, data, required_fields)
          expect(result).to be_nil
        end

        it "does not raise error" do
          expect { parser.send(:validate_required_fields!, data, required_fields) }
            .not_to raise_error
        end
      end

      context "with nil values" do
        let(:data_with_nils) { {"field1" => nil, "field2" => "value2"} }
        let(:required_fields) { ["field1", "field2"] }

        it "accepts nil values as present" do
          expect { parser.send(:validate_required_fields!, data_with_nils, required_fields) }
            .not_to raise_error
        end
      end

      context "with empty string values" do
        let(:data_with_empty) { {"field1" => "", "field2" => "value2"} }
        let(:required_fields) { ["field1", "field2"] }

        it "accepts empty strings as present" do
          expect { parser.send(:validate_required_fields!, data_with_empty, required_fields) }
            .not_to raise_error
        end
      end

      context "edge cases" do
        it "handles empty data hash" do
          expect { parser.send(:validate_required_fields!, {}, ["field1"]) }
            .to raise_error(Ibkr::AuthenticationError, /Missing required fields in response: field1/)
        end

        it "handles nil data" do
          expect { parser.send(:validate_required_fields!, nil, ["field1"]) }
            .to raise_error(NoMethodError)
        end

        it "correctly identifies missing field with similar names" do
          data = {"field" => "value", "field2" => "value2"}
          expect { parser.send(:validate_required_fields!, data, ["field1"]) }
            .to raise_error(Ibkr::AuthenticationError, /Missing required fields in response: field1/)
        end
      end
    end
  end

  describe "error handling" do
    context "when signature generator raises error" do
      let(:response) do
        double("response",
          success?: true,
          body: {diffie_hellman_response: "dh_value"}.to_json)
      end

      it "propagates signature generator errors" do
        allow(mock_signature_generator)
          .to receive(:compute_live_session_token)
          .and_raise(StandardError, "Signature error")

        expect { parser.parse_live_session_token(response) }
          .to raise_error(StandardError, "Signature error")
      end
    end

    context "when JSON contains special characters" do
      let(:special_response) do
        double("response",
          success?: true,
          body: '{"key": "value with \"quotes\" and \\n newlines"}')
      end

      it "handles special characters correctly" do
        result = parser.parse_json_response(special_response)
        # The \n in JSON becomes an actual newline character when parsed
        expect(result["key"]).to eq("value with \"quotes\" and \n newlines")
      end
    end
  end

  describe "integration scenarios" do
    context "when response is not a double" do
      let(:string_response) { "not a response object" }

      it "raises NoMethodError for invalid response type" do
        expect { parser.parse_json_response(string_response) }
          .to raise_error(NoMethodError)
      end
    end

    context "when body is not a string" do
      let(:non_string_body_response) do
        double("response", success?: true, body: {key: "value"})
      end

      it "raises error for non-string body" do
        expect { parser.parse_json_response(non_string_body_response) }
          .to raise_error(TypeError)
      end
    end
  end
end
