# frozen_string_literal: true

require "ibkr"
require "dry-struct"
require "faraday"
require "openssl"
require "base64"
require "securerandom"
require "zlib"
require "stringio"
require "json"

# Load shared contexts and examples
require_relative "support/shared_contexts"
require_relative "support/shared_examples"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Filter test types
  config.define_derived_metadata(file_path: %r{/spec/features/}) do |metadata|
    metadata[:type] = :feature
  end

  config.define_derived_metadata(file_path: %r{/spec/lib/}) do |metadata|
    metadata[:type] = :unit
  end

  # Mock Rails environment for testing
  config.before(:each) do
    # Stub Rails if not already defined
    unless defined?(Rails)
      Rails = double("Rails",
        logger: double("logger", error: nil, debug: nil),
        application: double("application",
          credentials: double("credentials",
            ibkr: double("ibkr",
              oauth: double("oauth",
                consumer_key: "test_consumer_key",
                access_token: "test_access_token",
                access_token_secret: Base64.encode64("test_secret"),
                base_url: "https://api.ibkr.com"
              )
            )
          )
        )
      )
    end

    # Stub ActiveSupport::SecurityUtils if not available
    unless defined?(ActiveSupport::SecurityUtils)
      ActiveSupport = Module.new unless defined?(ActiveSupport)
      ActiveSupport::SecurityUtils = Module.new
      ActiveSupport::SecurityUtils.define_singleton_method(:secure_compare) do |a, b|
        a == b
      end
    end
  end

  # Performance testing helpers
  config.around(:each, :performance) do |example|
    start_time = Time.now
    example.run
    end_time = Time.now
    
    if (end_time - start_time) > 1.0  # Warn if test takes longer than 1 second
      puts "⚠️  Slow test: #{example.metadata[:full_description]} (#{(end_time - start_time).round(2)}s)"
    end
  end

  # Security test helpers
  config.before(:each, :security) do
    # Additional security-focused test setup
    @original_openssl_verify_mode = OpenSSL::SSL::VERIFY_PEER
  end

  # Integration test setup
  config.before(:each, :integration) do
    # Skip integration tests by default unless explicitly requested
    skip "Integration tests require IBKR_RUN_INTEGRATION_TESTS=true" unless ENV["IBKR_RUN_INTEGRATION_TESTS"]
  end
end
