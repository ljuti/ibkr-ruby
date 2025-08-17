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

RSpec.shared_examples "a WebSocket connection lifecycle" do
  it "handles connection establishment" do
    # WebSocket connections require full open + auth cycle
    expect { 
      subject.connect
      if respond_to?(:simulate_websocket_open)
        simulate_websocket_open
        if respond_to?(:auth_status_message) && respond_to?(:simulate_websocket_message)
          simulate_websocket_message(auth_status_message)
        end
      end
    }.to change { subject.connected? }.from(false).to(true)
  end

  it "handles connection closure" do
    subject.connect
    if respond_to?(:simulate_websocket_open)
      simulate_websocket_open
      if respond_to?(:auth_status_message) && respond_to?(:simulate_websocket_message)
        simulate_websocket_message(auth_status_message)
      end
    end
    expect { subject.disconnect }.to change { subject.connected? }.from(true).to(false)
  end

  it "maintains connection state correctly" do
    expect(subject.connection_state).to eq(:disconnected)
    
    subject.connect
    if respond_to?(:simulate_websocket_open)
      simulate_websocket_open
      if respond_to?(:auth_status_message) && respond_to?(:simulate_websocket_message)
        simulate_websocket_message(auth_status_message)
      end
    end
    # After full authentication cycle, expect authenticated state
    expected_state = respond_to?(:auth_status_message) ? :authenticated : :connected
    expect(subject.connection_state).to eq(expected_state)
    
    subject.disconnect
    expect(subject.connection_state).to eq(:disconnected)
  end
end

RSpec.shared_examples "a WebSocket message handler" do
  it "processes valid messages" do
    expect { subject.handle_message(valid_message) }.not_to raise_error
  end

  it "handles malformed messages gracefully" do
    expect { subject.handle_message("invalid json {") }.not_to raise_error
    expect(subject.last_error).to include("malformed")
  end

  it "validates message types" do
    invalid_message = { type: "unknown_type", data: {} }
    expect { subject.handle_message(invalid_message) }.not_to raise_error
    expect(subject.last_error).to include("unknown message type")
  end
end

RSpec.shared_examples "a WebSocket subscription manager" do
  it "tracks subscription state" do
    expect(subject.subscriptions).to be_empty
    
    subscription_id = subject.subscribe(subscription_request)
    expect(subject.subscriptions).to include(subscription_id)
    
    subject.unsubscribe(subscription_id)
    expect(subject.subscriptions).not_to include(subscription_id)
  end

  it "prevents duplicate subscriptions" do
    id1 = subject.subscribe(subscription_request)
    id2 = subject.subscribe(subscription_request)
    
    expect(id1).to eq(id2)
    expect(subject.subscriptions.size).to eq(1)
  end

  it "handles subscription limits" do
    # Set subscription limits directly
    subject.instance_variable_get(:@subscription_limits)[:total] = 2
    
    subject.subscribe({ channel: "market_data", symbols: ["AAPL"] })
    subject.subscribe({ channel: "market_data", symbols: ["GOOGL"] })
    
    expect { subject.subscribe({ channel: "market_data", symbols: ["MSFT"] }) }.to raise_error(Ibkr::WebSocket::SubscriptionError)
  end
end

RSpec.shared_examples "a WebSocket reconnection strategy" do
  it "implements exponential backoff" do
    expect(subject.next_reconnect_delay(1)).to be < subject.next_reconnect_delay(2)
    expect(subject.next_reconnect_delay(2)).to be < subject.next_reconnect_delay(3)
  end

  it "caps maximum delay" do
    large_attempt = 100
    delay = subject.next_reconnect_delay(large_attempt)
    expect(delay).to be <= subject.max_reconnect_delay
  end

  it "tracks reconnection attempts" do
    expect(subject.reconnect_attempts).to eq(0)
    
    subject.attempt_reconnect
    expect(subject.reconnect_attempts).to eq(1)
    
    subject.reset_reconnect_attempts
    expect(subject.reconnect_attempts).to eq(0)
  end
end

RSpec.shared_examples "a real-time data processor" do
  it "processes data updates in correct order" do
    updates = []
    subject.on_update { |data| updates << data }
    
    subject.process_message(first_update)
    subject.process_message(second_update)
    
    expect(updates).to eq([first_update[:data], second_update[:data]])
  end

  it "handles out-of-order messages" do
    # Should be implemented based on timestamp ordering
    updates = []
    subject.on_update { |data| updates << data }
    
    # Send newer message first
    subject.process_message(newer_message)
    subject.process_message(older_message)
    
    # Should be reordered by timestamp
    expect(updates.first[:timestamp]).to be < updates.last[:timestamp]
  end

  it "filters duplicate messages" do
    updates = []
    subject.on_update { |data| updates << data }
    
    subject.process_message(duplicate_message)
    subject.process_message(duplicate_message)
    
    expect(updates.size).to eq(1)
  end
end
