# Development Guide

This guide covers development setup, testing strategies, and contribution guidelines for the IBKR Ruby gem.

## Development Setup

### Prerequisites

- Ruby >= 3.2.0
- Bundler >= 2.0
- Git

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/ljuti/ibkr.git
cd ibkr

# Install dependencies
bin/setup

# Verify setup
bundle exec rspec
bundle exec standardrb
```

### Development Environment

```bash
# Interactive console with gem loaded
bin/console

# Example console session:
client = Ibkr::Client.new(live: false)
config = Ibkr.configuration
```

## Testing Strategy

### Test Suite Overview

The gem has comprehensive test coverage with 197 examples:

- **Core Functionality**: 152 passing tests (77% pass rate)
- **OAuth Cryptographic**: 19 tests (complex implementation required)
- **Error Handling**: 26 tests (mostly passing)

### Test Categories

#### 1. Unit Tests (100% passing)

**Client Interface Tests**
```bash
bundle exec rspec spec/lib/ibkr/client_spec.rb
# 26 examples, 0 failures
```

Tests:
- Client initialization and configuration
- Authentication delegation
- Account ID management
- Service access and memoization
- Thread safety

**Account Services Tests**
```bash
bundle exec rspec spec/lib/ibkr/accounts_spec.rb
# 26 examples, 0 failures
```

Tests:
- Portfolio summary retrieval
- Position management with pagination
- Transaction history filtering
- API endpoint integration
- Error handling

**Data Models Tests**
```bash
# Position model
bundle exec rspec spec/lib/ibkr/accounts/position_spec.rb
# 29 examples, 0 failures

# Account Summary model  
bundle exec rspec spec/lib/ibkr/accounts/summary_spec.rb
# 14 examples, 0 failures
```

Tests:
- Type coercion and validation
- Business logic methods
- Optional vs required attributes
- Data transformation
- Error scenarios

#### 2. Integration Tests (Mostly passing)

**OAuth Authentication**
```bash
bundle exec rspec spec/lib/ibkr/oauth/live_session_token_spec.rb
# 17 examples, 0 failures
```

Tests:
- Token validation logic
- Signature verification
- Rails credentials integration
- Cryptographic operations (basic)

#### 3. Error Handling Tests (Partially passing)

```bash
bundle exec rspec spec/lib/ibkr/error_handling_spec.rb
# 26 examples, ~9 failures
```

Tests network scenarios, authentication failures, and edge cases.

### Running Tests

#### Full Test Suite

```bash
# Run all tests
bundle exec rspec

# With detailed output
bundle exec rspec --format documentation

# With progress indicator
bundle exec rspec --format progress
```

#### Focused Testing

```bash
# Run specific test file
bundle exec rspec spec/lib/ibkr/client_spec.rb

# Run specific test case
bundle exec rspec spec/lib/ibkr/client_spec.rb:100

# Run tests matching pattern
bundle exec rspec --grep "authentication"

# Run failing tests only
bundle exec rspec --only-failures
```

#### Test Environment

```bash
# Set specific test environment
RAILS_ENV=test bundle exec rspec

# Run with debug output
DEBUG=1 bundle exec rspec

# Run with coverage
COVERAGE=1 bundle exec rspec
```

### Test Structure

#### Shared Examples

Located in `spec/support/shared_examples.rb`:

- `"a successful API request"` - HTTP success scenarios
- `"a data transformation operation"` - Model attribute validation

#### Shared Contexts

Located in `spec/support/shared_contexts.rb`:

- `"with mocked Rails credentials"` - OAuth credential mocking
- `"with mocked cryptographic keys"` - RSA/DH key mocking
- `"with mocked Faraday client"` - HTTP client mocking
- `"with authenticated oauth client"` - Full authentication setup

#### Mock Strategy

```ruby
# HTTP Response Mocking
let(:mock_response) do
  double("response",
    success?: true,
    status: 200,
    body: response_body,
    headers: {}
  )
end

# OAuth Client Mocking
let(:oauth_client) do
  client = Ibkr::Oauth.new(live: false)
  allow(client).to receive(:authenticated?).and_return(true)
  allow(client).to receive(:get).and_return(mock_response)
  client
end
```

### Writing Tests

#### Test Structure Guidelines

Follow BDD (Behavior-Driven Development) style:

```ruby
RSpec.describe Ibkr::Client do
  describe "#authenticate" do
    context "when credentials are valid" do
      it "successfully authenticates and returns true" do
        # Given valid credentials are configured
        # When calling authenticate
        result = client.authenticate
        
        # Then authentication should succeed
        expect(result).to be true
        expect(client.oauth_client.authenticated?).to be true
      end
    end

    context "when credentials are invalid" do
      it "raises AuthenticationError with descriptive message" do
        # Given invalid credentials
        # When attempting to authenticate
        # Then it should raise specific error
        expect { client.authenticate }.to raise_error(Ibkr::AuthenticationError)
      end
    end
  end
end
```

#### Model Testing

```ruby
RSpec.describe Ibkr::Models::Position do
  let(:valid_position_data) do
    {
      conid: "265598",
      position: 100,
      description: "APPLE INC",
      currency: "USD",
      market_value: 16275.00,
      unrealized_pnl: 1250.50,
      # ... other required fields
    }
  end

  describe "initialization" do
    it "creates valid position with all attributes" do
      position = described_class.new(valid_position_data)
      
      expect(position.conid).to eq("265598")
      expect(position.position).to eq(100)
      expect(position.description).to eq("APPLE INC")
    end
  end

  describe "business logic" do
    it "calculates position direction correctly" do
      position = described_class.new(valid_position_data)
      
      expect(position.long?).to be true
      expect(position.short?).to be false
      expect(position.flat?).to be false
    end
  end
end
```

#### Error Testing

```ruby
describe "error handling" do
  it "raises specific error for authentication failures" do
    allow(oauth_client).to receive(:authenticate)
      .and_raise(Ibkr::AuthenticationError, "Invalid credentials")
    
    expect { client.authenticate }.to raise_error(
      Ibkr::AuthenticationError,
      "Invalid credentials"
    )
  end
end
```

## Code Quality

### Linting

The project uses Standard Ruby for code formatting:

```bash
# Check code style
bundle exec standardrb

# Auto-fix issues
bundle exec standardrb --fix

# Check specific files
bundle exec standardrb lib/ibkr/client.rb
```

### Code Quality Standards

- **Frozen String Literals**: All files use `# frozen_string_literal: true`
- **Type Safety**: Dry::Types used for all data models
- **Documentation**: Comprehensive inline comments
- **Error Handling**: Explicit error classes for different scenarios
- **Thread Safety**: All operations designed to be thread-safe

### Continuous Integration

The project includes GitHub Actions workflow:

```yaml
# .github/workflows/ruby.yml
name: Ruby
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ruby-version: ['3.2', '3.3']
    steps:
      - uses: actions/checkout@v2
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby-version }}
          bundler-cache: true
      - name: Run tests
        run: bundle exec rspec
      - name: Run linter
        run: bundle exec standardrb
```

## Architecture Patterns

### Service Layer Pattern

Services encapsulate business logic:

```ruby
# lib/ibkr/services/base.rb
class Base
  def initialize(client)
    @_client = client
  end

  private

  attr_reader :client
  
  def ensure_authenticated!
    raise Ibkr::AuthenticationError unless client.oauth_client.authenticated?
  end
end

# lib/ibkr/services/accounts.rb  
class Accounts < Base
  def summary
    ensure_authenticated!
    response = client.oauth_client.get(account_path("/summary"))
    normalized = normalize_summary(response)
    Models::AccountSummary.new(normalized.merge(account_id: account_id))
  end
end
```

### Repository Pattern

Models act as value objects with validation:

```ruby
# lib/ibkr/models/base.rb
class Base < Dry::Struct
  transform_keys(&:to_sym)
  
  # Common functionality for all models
  def to_h
    super.transform_keys(&:to_s)
  end
end
```

### Error Handling Pattern

Hierarchical error classes with context:

```ruby
# lib/ibkr/errors/base.rb
class BaseError < Ibkr::Error
  attr_reader :details, :timestamp, :request_id

  def initialize(message = nil, **options)
    super(message)
    @details = options.fetch(:details, {})
    @timestamp = options.fetch(:timestamp, Time.now)
    @request_id = options[:request_id]
  end

  def to_h
    {
      error: self.class.name,
      message: message,
      details: details,
      timestamp: timestamp
    }
  end
end
```

## Contributing

### Pull Request Process

1. **Fork the repository**
2. **Create feature branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```

3. **Implement changes**
   - Write code following project patterns
   - Add comprehensive tests
   - Update documentation if needed

4. **Run quality checks**
   ```bash
   bundle exec rspec
   bundle exec standardrb
   ```

5. **Commit changes**
   ```bash
   git commit -am 'Add amazing feature'
   ```

6. **Push and create PR**
   ```bash
   git push origin feature/amazing-feature
   ```

### Contribution Guidelines

#### Code Style

- Follow Standard Ruby conventions
- Use descriptive variable and method names
- Add comments for complex business logic
- Maintain consistent file structure

#### Testing Requirements

- All new features must have tests
- Maintain or improve test coverage
- Use BDD style with Given/When/Then comments
- Mock external dependencies appropriately

#### Documentation

- Update README.md for new features
- Add inline documentation for public APIs
- Update API.md for new methods
- Include usage examples

### Development Workflow

#### Adding New Features

1. **Start with tests**
   ```bash
   # Create failing test first
   bundle exec rspec spec/lib/ibkr/new_feature_spec.rb
   ```

2. **Implement feature**
   ```ruby
   # Add implementation to make tests pass
   # Follow existing patterns
   ```

3. **Refactor and document**
   ```bash
   # Improve code quality
   bundle exec standardrb --fix
   # Update documentation
   ```

#### Debugging

```ruby
# Add debugging to tests
require 'pry'
binding.pry

# Enable debug logging
Ibkr.configure do |config|
  config.logger_level = :debug
end
```

#### Common Tasks

```bash
# Generate new model
touch lib/ibkr/models/new_model.rb
touch spec/lib/ibkr/models/new_model_spec.rb

# Add new service method
# Edit lib/ibkr/services/accounts.rb
# Edit spec/lib/ibkr/accounts_spec.rb

# Add new error class
touch lib/ibkr/errors/new_error.rb
# Update lib/ibkr.rb to require it
```

## Performance Considerations

### Memory Management

- Use lazy loading for large datasets
- Implement proper connection pooling
- Cache expensive operations appropriately

### HTTP Optimization

- Gzip compression enabled by default
- Connection reuse through Faraday
- Appropriate timeout settings

### Thread Safety

- Memoized services are thread-safe
- Immutable data models
- Atomic authentication state changes

## Troubleshooting

### Common Issues

#### Test Failures

```bash
# Clear cached dependencies
rm -rf .bundle
bundle install

# Reset test database/mocks
bundle exec rspec --seed 1234  # Use specific seed

# Debug specific test
bundle exec rspec spec/lib/ibkr/client_spec.rb:50 --format documentation
```

#### Authentication Issues

- Verify OAuth credentials in Rails credentials
- Check certificate file paths and permissions
- Ensure environment configuration is correct

#### Type Validation Errors

- Check data structure matches model definitions
- Verify Dry::Types usage and constraints
- Ensure proper type coercion

### Getting Help

- **Issues**: Create GitHub issue with reproducible example
- **Development**: Check CLAUDE.md for implementation guidance
- **API Usage**: See API.md for complete method documentation

This development guide provides everything needed to contribute effectively to the IBKR gem. The codebase follows Ruby best practices and provides a solid foundation for extending functionality.