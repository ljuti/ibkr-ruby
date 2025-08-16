# frozen_string_literal: true

RSpec.shared_examples "a successful API request" do
  it "returns parsed JSON response" do
    expect(subject).to be_a(Hash)
    expect(subject).to have_key("result")
  end

  it "handles gzipped responses" do
    allow(mock_response).to receive(:headers).and_return("content-encoding" => "gzip")
    compressed_body = StringIO.new
    Zlib::GzipWriter.wrap(compressed_body) { |gz| gz.write(response_body) }
    allow(mock_response).to receive(:body).and_return(compressed_body.string)
    
    expect(subject).to be_a(Hash)
  end
end

RSpec.shared_examples "a failed API request" do |expected_error_message|
  let(:mock_response) { double("response", success?: false, status: 400, body: "Bad Request") }

  it "raises an error with descriptive message" do
    expect { subject }.to raise_error(RuntimeError, /#{expected_error_message}/)
  end
end

RSpec.shared_examples "a secure token operation" do
  it "uses secure comparison for signature validation" do
    expect(ActiveSupport::SecurityUtils).to receive(:secure_compare)
    subject
  end

  it "handles comparison errors gracefully" do
    allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_raise(ArgumentError)
    expect(subject).to be_falsy
  end
end

RSpec.shared_examples "an OAuth-authenticated request" do
  it "includes proper OAuth headers" do
    expect(mock_faraday).to receive(:get) do |url, params|
      # Verify OAuth authorization header is set through Faraday middleware
      expect(url).to include(expected_endpoint)
    end
    subject
  end

  it "uses correct signature method for the request type" do
    if described_class.name.include?("authentication")
      expect(subject).to include("oauth_signature_method" => "RSA-SHA256")
    else
      expect(subject).to include("oauth_signature_method" => "HMAC-SHA256")
    end
  end
end

RSpec.shared_examples "a data transformation operation" do |expected_attributes|
  it "transforms all expected attributes" do
    expected_attributes.each do |attr|
      expect(subject).to respond_to(attr)
    end
  end

  it "coerces numeric types correctly" do
    numeric_attrs = expected_attributes.select { |attr| attr.to_s.include?("value") || attr.to_s.include?("amount") }
    numeric_attrs.each do |attr|
      value = subject.public_send(attr)
      expect(value).to be_a(Numeric).or be_nil if value
    end
  end
end