# IBKR Ruby Client - Comprehensive BDD Testing Strategy

## Overview

This document outlines a comprehensive Behavior-Driven Development (BDD) testing strategy for the Interactive Brokers Ruby API client. The strategy focuses on behavior rather than implementation details, ensuring tests serve as living documentation while providing thorough coverage of the complex financial and cryptographic operations.

## Testing Philosophy

### BDD Principles Applied

1. **Given-When-Then Structure**: All tests follow clear Given-When-Then patterns that describe business scenarios
2. **Behavior Over Implementation**: Tests focus on what the system should do, not how it does it
3. **Living Documentation**: Test descriptions serve as executable specifications that stakeholders can understand
4. **Outside-In Development**: Feature tests drive the design of unit tests and implementation

### Test Pyramid Structure

```
    /\
   /  \    E2E/Integration Tests (Few)
  /____\   Feature Tests (Some)
 /______\  Unit Tests (Many)
/__________\ 
```

## Test Categories

### 1. Feature Tests (`spec/features/`)

**Purpose**: Test complete user journeys and business workflows

**Key Scenarios**:
- Authentication flow (sandbox vs live)
- Portfolio management operations
- Session lifecycle management
- Multi-account switching

**Example Structure**:
```ruby
describe "User authenticates with Interactive Brokers" do
  context "when user wants to connect to sandbox environment" do
    it "successfully establishes a secure session"
    it "handles authentication failures gracefully"
  end
end
```

### 2. Unit Tests (`spec/lib/`)

**Purpose**: Test individual components in isolation with comprehensive edge cases

**Components Covered**:
- `Ibkr::Client` - Main client interface
- `Ibkr::Oauth` - Authentication and API communication
- `Ibkr::Oauth::LiveSessionToken` - Token lifecycle management
- `Ibkr::Accounts` - Portfolio and account operations
- Data models (`Summary`, `Position`, `Transaction`)

## Security-Focused Testing

### Cryptographic Operations Testing

**RSA-SHA256 Signature Generation**:
- Signature generation with proper key handling
- Base string construction and encoding
- Error handling for key loading failures

**HMAC-SHA256 for API Requests**:
- Signature generation with live session tokens
- URL encoding and parameter handling
- Token decoding and validation

**Diffie-Hellman Key Exchange**:
- Secure random number generation
- Mathematical operations validation
- Key derivation and shared secret computation

**Security Validations**:
```ruby
it_behaves_like "a secure token operation" do
  subject { token.valid_signature? }
end
```

### Token Security Testing

- Constant-time comparison to prevent timing attacks
- Expiration handling and validation
- Signature verification integrity
- Secure error handling without information leakage

## Mock and Stub Strategy

### External Dependencies

**Rails Framework**:
- Mock Rails.application.credentials for configuration
- Stub Rails.logger for error handling tests
- Mock ActiveSupport::SecurityUtils for secure comparisons

**Cryptographic Operations**:
- Mock OpenSSL key loading and operations
- Stub file system access for certificate files
- Mock secure random number generation for predictable tests

**HTTP Communication**:
- Mock Faraday HTTP client for API calls
- Stub response parsing and gzip decompression
- Mock network error scenarios (timeouts, connection failures)

### Shared Contexts

```ruby
# Comprehensive mocking setup
include_context "with mocked Rails credentials"
include_context "with mocked cryptographic keys"
include_context "with authenticated oauth client"
```

## Data Model Testing

### Dry::Struct Validation

**Type Coercion Testing**:
- String to numeric conversion for financial data
- Currency and timestamp handling
- Optional attribute management

**Validation Testing**:
- Required field validation
- Type mismatch error handling
- Edge cases with nil/empty values

**Real-World Scenarios**:
- Multi-currency account data
- Large position portfolios
- Zero positions (closed trades)
- International securities

## Error Handling and Edge Cases

### Network and Connectivity Errors

**Connection Failures**:
- IBKR API unavailability
- Network timeouts during authentication
- DNS resolution failures

**HTTP Status Code Handling**:
- 401 Unauthorized (invalid credentials)
- 403 Forbidden (insufficient permissions)
- 429 Rate Limited (with retry-after guidance)
- 500 Internal Server Error (IBKR system issues)
- 503 Service Unavailable (temporary outages)

### Data Integrity Errors

**Malformed Responses**:
- Invalid JSON parsing
- Unexpected data structures
- Missing required fields
- Corrupted gzip data

**Numeric Data Issues**:
- NaN and Infinity values in financial data
- Invalid currency codes
- Negative values in unexpected fields

### Security and Configuration Errors

**Certificate and Key Management**:
- Missing cryptographic files
- Invalid key formats
- Permission denied errors

**Configuration Issues**:
- Missing Rails credentials
- Environment misconfiguration
- Live vs sandbox mode conflicts

## Performance and Scalability Testing

### Large Dataset Handling

**Memory Management**:
- Large position lists (10,000+ securities)
- Extensive transaction history
- JSON parsing with large responses

**Cryptographic Performance**:
- RSA operations timing
- HMAC calculation efficiency
- DH key exchange performance

### Concurrency Testing

**Thread Safety**:
- Multiple threads accessing same client
- Concurrent API requests
- Authentication state consistency

## Test Organization Best Practices

### File Structure

```
spec/
├── features/                    # Feature-level BDD scenarios
│   ├── authentication_flow_spec.rb
│   └── portfolio_management_spec.rb
├── lib/
│   └── ibkr/
│       ├── client_spec.rb       # Main client interface
│       ├── oauth_spec.rb        # Authentication component
│       ├── accounts_spec.rb     # Portfolio operations
│       ├── accounts/
│       │   ├── summary_spec.rb  # Data model testing
│       │   └── position_spec.rb
│       └── oauth/
│           ├── live_session_token_spec.rb
│           └── cryptographic_operations_spec.rb
├── support/
│   ├── shared_contexts.rb       # Reusable test setup
│   └── shared_examples.rb       # Reusable behavior specs
└── spec_helper.rb               # Global test configuration
```

### Naming Conventions

**Describe Blocks**: Use class or module names
```ruby
describe Ibkr::Oauth::LiveSessionToken do
```

**Context Blocks**: Describe conditions or state
```ruby
context "when token is expired" do
context "with valid credentials" do
```

**It Blocks**: Describe expected behavior
```ruby
it "validates signature using HMAC-SHA1 with consumer key"
it "handles authentication failures gracefully"
```

### Shared Examples

**Reusable Behavior Patterns**:
- `"a successful API request"` - JSON parsing and gzip handling
- `"a failed API request"` - Error message validation
- `"a secure token operation"` - Security validation patterns
- `"a data transformation operation"` - Model validation patterns

## Running Tests

### Test Categories

```bash
# Run all tests
bundle exec rspec

# Run only feature tests
bundle exec rspec spec/features/

# Run only unit tests
bundle exec rspec spec/lib/

# Run security-focused tests
bundle exec rspec --tag security

# Run performance tests with timing
bundle exec rspec --tag performance
```

### Integration Testing

```bash
# Enable integration tests (requires actual IBKR credentials)
IBKR_RUN_INTEGRATION_TESTS=true bundle exec rspec --tag integration
```

### Coverage and Reporting

```bash
# Generate coverage report
COVERAGE=true bundle exec rspec

# Verbose output for debugging
bundle exec rspec --format documentation
```

## Continuous Integration Considerations

### Test Isolation

- No shared state between tests
- Clean mocks and stubs for each test
- Isolated cryptographic operations

### Security in CI

- No real credentials in test environment
- Mocked cryptographic operations
- Secure handling of test certificates

### Performance Monitoring

- Identify slow tests (>1 second warning)
- Memory usage monitoring for large datasets
- Cryptographic operation timing

## Contributing Guidelines

### Adding New Tests

1. **Start with Feature Tests**: Describe the user journey
2. **Add Unit Tests**: Cover implementation details
3. **Include Edge Cases**: Error conditions and security scenarios
4. **Use Shared Examples**: Leverage reusable behavior patterns
5. **Follow BDD Structure**: Given-When-Then in descriptions

### Test Quality Standards

- Tests must describe behavior, not implementation
- All error scenarios must be covered
- Security-critical operations require dedicated test coverage
- Performance implications should be considered for financial data operations

This comprehensive testing strategy ensures the IBKR Ruby client is thoroughly tested from both behavioral and technical perspectives, providing confidence in its security, reliability, and performance for financial trading operations.