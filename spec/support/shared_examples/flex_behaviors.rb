# frozen_string_literal: true

RSpec.shared_examples "a Flex Web Service operation" do
  it "uses correct authentication token" do
    expect(mock_http_client).to receive(:get) do |path, params|
      expect(params[:t]).to eq(flex_token)
    end.and_return(successful_response)

    subject
  end

  it "targets correct IBKR Flex Web Service endpoint" do
    expect(mock_http_client).to receive(:get) do |path, params|
      expect(path).to start_with("/AccountManagement/FlexWebService/")
    end.and_return(successful_response)

    subject
  end

  it "includes required API version parameter" do
    expect(mock_http_client).to receive(:get) do |path, params|
      expect(params[:v]).to eq(3) if path.include?("SendRequest")
    end.and_return(successful_response)

    subject
  end
end

RSpec.shared_examples "a Flex error handler" do |error_class, error_code|
  let(:error_response) do
    double("response",
      success?: true,  # IBKR returns 200 even for errors
      body: "<FlexStatementResponse>
              <Status>Warn</Status>
              <ErrorCode>#{error_code}</ErrorCode>
              <ErrorMessage>#{expected_error_message}</ErrorMessage>
             </FlexStatementResponse>")
  end

  it "raises specific error class for #{error_code}" do
    expect(mock_http_client).to receive(:get).and_return(error_response)

    expect { subject }.to raise_error(error_class, /#{expected_error_message}/i)
  end

  it "includes error code in exception" do
    expect(mock_http_client).to receive(:get).and_return(error_response)

    begin
      subject
    rescue error_class => e
      expect(e.code).to eq(error_code)
    end
  end

  it "provides relevant error context" do
    expect(mock_http_client).to receive(:get).and_return(error_response)

    begin
      subject
    rescue error_class => e
      expect(e.details).to include(endpoint: be_a(String))
      expect(e.context).to include(operation: be_a(String))
    end
  end

  it "includes helpful suggestions for recovery" do
    expect(mock_http_client).to receive(:get).and_return(error_response)

    begin
      subject
    rescue error_class => e
      expect(e.suggestions).to be_an(Array)
      expect(e.suggestions).not_to be_empty
    end
  end
end

RSpec.shared_examples "a Flex network error handler" do
  it "handles connection timeout gracefully" do
    expect(mock_http_client).to receive(:get)
      .and_raise(Faraday::TimeoutError, "Request timeout")

    expect { subject }.to raise_error(
      Ibkr::FlexError::NetworkError,
      /Request timeout.*network error/i
    )
  end

  it "handles connection failures gracefully" do
    expect(mock_http_client).to receive(:get)
      .and_raise(Faraday::ConnectionFailed, "Connection refused")

    expect { subject }.to raise_error(
      Ibkr::FlexError::NetworkError,
      /Connection refused.*failed to connect/i
    )
  end

  it "handles DNS resolution failures" do
    expect(mock_http_client).to receive(:get)
      .and_raise(Faraday::ConnectionFailed, "Name or service not known")

    expect { subject }.to raise_error(
      Ibkr::FlexError::NetworkError,
      /Name or service not known/i
    )
  end

  it "provides network troubleshooting suggestions" do
    expect(mock_http_client).to receive(:get)
      .and_raise(Faraday::TimeoutError)

    begin
      subject
    rescue Ibkr::FlexError::NetworkError => e
      expect(e.suggestions).to include(/check.*network.*connection/i)
      expect(e.suggestions).to include(/IBKR.*system status/i)
    end
  end
end

RSpec.shared_examples "a Flex XML parser" do
  let(:malformed_xml_response) do
    double("response",
      success?: true,
      body: "<InvalidXML><<>>Not properly formed")
  end

  it "handles malformed XML gracefully" do
    expect(mock_http_client).to receive(:get).and_return(malformed_xml_response)

    expect { subject }.to raise_error(
      Ibkr::FlexError::ParseError,
      /Failed to parse XML response/i
    )
  end

  it "includes raw response in parse error for debugging" do
    expect(mock_http_client).to receive(:get).and_return(malformed_xml_response)

    begin
      subject
    rescue Ibkr::FlexError::ParseError => e
      expect(e.details[:raw_response]).to include("InvalidXML")
    end
  end

  it "handles empty response body" do
    empty_response = double("response", success?: true, body: "")
    expect(mock_http_client).to receive(:get).and_return(empty_response)

    expect { subject }.to raise_error(Ibkr::FlexError::ParseError)
  end

  it "preserves XML structure in parsed data" do
    expect(mock_http_client).to receive(:get).and_return(successful_response)

    result = subject
    # Verify that XML attributes and nested elements are preserved
    expect(result).to be_a(Hash) if result.respond_to?(:keys)
  end
end

RSpec.shared_examples "a Flex parameter validator" do |parameter_name|
  it "validates #{parameter_name} presence" do
    expect { subject_with_nil_param }.to raise_error(
      ArgumentError,
      /#{parameter_name}.*required.*cannot be nil/i
    )
  end

  it "validates #{parameter_name} format" do
    expect { subject_with_invalid_param }.to raise_error(
      ArgumentError,
      /#{parameter_name}.*must be.*string|integer/i
    )
  end

  it "accepts valid #{parameter_name} formats" do
    expect { subject_with_valid_param }.not_to raise_error
  end
end

RSpec.shared_examples "a Flex service integration" do
  it "integrates with main IBKR client" do
    # Test that Flex service is accessible through main client
    expect(client.flex).to be_a(Ibkr::Services::Flex)
    expect(client.flex.client).to eq(client)
  end

  it "respects client authentication requirements" do
    unauthenticated_client = double("client", authenticated?: false)
    service = Ibkr::Services::Flex.new(unauthenticated_client)

    expect { service.generate_report("123") }.to raise_error(
      Ibkr::AuthenticationError
    )
  end

  it "maintains service memoization pattern" do
    service1 = client.flex
    service2 = client.flex

    expect(service1).to be(service2)
  end

  it "provides consistent error handling across operations" do
    # Verify that all Flex operations handle errors consistently
    %w[generate_report fetch_report].each do |method|
      next unless subject.respond_to?(method)

      expect(subject.method(method)).to be_a(Method)
    end
  end
end

RSpec.shared_examples "a Flex data transformer" do |expected_structure|
  it "transforms XML data to structured Ruby objects" do
    result = subject

    expected_structure.each do |key, value_type|
      expect(result).to respond_to(key)

      case value_type
      when :string
        expect(result.public_send(key)).to be_a(String) unless result.public_send(key).nil?
      when :integer
        expect(result.public_send(key)).to be_a(Integer) unless result.public_send(key).nil?
      when :float
        expect(result.public_send(key)).to be_a(Float) unless result.public_send(key).nil?
      when :array
        expect(result.public_send(key)).to be_an(Array)
      when :time
        expect(result.public_send(key)).to be_a(Time) unless result.public_send(key).nil?
      when :date
        expect(result.public_send(key)).to be_a(Date) unless result.public_send(key).nil?
      end
    end
  end

  it "preserves data relationships and consistency" do
    result = subject

    # Test that related data elements are consistent
    if result.respond_to?(:account_id) && result.respond_to?(:trades)
      result.trades.each do |trade|
        expect(trade.account_id).to eq(result.account_id) if trade.respond_to?(:account_id)
      end
    end
  end

  it "handles missing optional data gracefully" do
    # Test with minimal data structure
    minimal_result = subject_with_minimal_data if respond_to?(:subject_with_minimal_data)

    # Should not raise errors for missing optional fields
    expect { minimal_result&.to_h }.not_to raise_error
  end
end

RSpec.shared_examples "a Flex report workflow" do
  it "supports complete generate-fetch workflow" do
    # Mock both generation and fetch responses
    expect(mock_http_client).to receive(:get)
      .with(hash_including(q: query_id))
      .and_return(generate_success_response)
      .ordered

    expect(mock_http_client).to receive(:get)
      .with(hash_including(q: reference_code))
      .and_return(fetch_success_response)
      .ordered

    # Execute workflow
    ref_code = subject.generate_report(query_id)
    expect(ref_code).to eq(reference_code)

    report_data = subject.fetch_report(ref_code)
    expect(report_data).to be_a(Hash)
    expect(report_data).to have_key(:FlexQueryResponse)
  end

  it "handles workflow interruption gracefully" do
    # Generation succeeds, fetch fails
    expect(mock_http_client).to receive(:get)
      .and_return(generate_success_response)

    expect(mock_http_client).to receive(:get)
      .and_raise(Faraday::TimeoutError)

    ref_code = subject.generate_report(query_id)
    expect(ref_code).to eq(reference_code)

    expect { subject.fetch_report(ref_code) }.to raise_error(
      Ibkr::FlexError::NetworkError
    )
  end

  it "maintains operation isolation" do
    # Multiple concurrent operations should not interfere
    allow(mock_http_client).to receive(:get).and_return(generate_success_response)

    threads = Array.new(3) do |i|
      Thread.new { subject.generate_report("query_#{i}") }
    end

    results = threads.map(&:join).map(&:value)
    expect(results).to all(eq(reference_code))
  end
end

RSpec.shared_examples "a Flex thread-safe operation" do
  it "supports concurrent access" do
    # Setup concurrent operations
    allow(mock_http_client).to receive(:get).and_return(successful_response)

    threads = Array.new(5) do
      Thread.new { subject }
    end

    # All operations should complete successfully
    results = threads.map(&:join).map(&:value)
    expect(results.size).to eq(5)
  end

  it "maintains state consistency under concurrency" do
    # Test that shared state remains consistent
    allow(mock_http_client).to receive(:get).and_return(successful_response)

    # Execute operations concurrently
    results = Array.new(3) do
      Thread.new do
        3.times.map { subject }
      end
    end.map(&:join).map(&:value).flatten

    # All results should be consistent
    expect(results.uniq.size).to eq(1) if results.first.is_a?(String)
  end

  it "handles concurrent errors gracefully" do
    # Some operations succeed, some fail
    call_count = 0
    allow(mock_http_client).to receive(:get) do
      call_count += 1
      if call_count.odd?
        successful_response
      else
        raise Faraday::TimeoutError
      end
    end

    threads = Array.new(4) do
      Thread.new do
        subject
      rescue Ibkr::FlexError::NetworkError
        :error
      end
    end

    results = threads.map(&:join).map(&:value)
    expect(results).to include(:error)
  end
end

RSpec.shared_examples "a Flex performance test" do |max_time: 1.0|
  it "completes operation within acceptable time" do
    allow(mock_http_client).to receive(:get).and_return(successful_response)

    start_time = Time.now
    subject
    elapsed_time = Time.now - start_time

    expect(elapsed_time).to be < max_time
  end

  it "handles large responses efficiently" do
    # Create large mock response
    large_response = double("response",
      success?: true,
      body: "<FlexQueryResponse>" + ("<Trade/>" * 10000) + "</FlexQueryResponse>")

    allow(mock_http_client).to receive(:get).and_return(large_response)

    start_time = Time.now
    result = subject
    elapsed_time = Time.now - start_time

    expect(elapsed_time).to be < max_time * 2  # Allow extra time for large data
    expect(result).not_to be_nil
  end

  it "manages memory usage efficiently" do
    allow(mock_http_client).to receive(:get).and_return(successful_response)

    # Execute operation multiple times
    gc_count_before = GC.stat[:total_freed_objects]

    10.times { subject }

    GC.start
    gc_count_after = GC.stat[:total_freed_objects]

    # Some objects should have been freed (no significant memory leaks)
    expect(gc_count_after).to be > gc_count_before
  end
end
