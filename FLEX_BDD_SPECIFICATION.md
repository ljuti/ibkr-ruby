# Comprehensive BDD Specification for IBKR Flex Web Service Integration

## Overview

This document outlines the comprehensive behavior-driven development (BDD) test suite designed for integrating IBKR's Flex Web Service into the Ruby gem. The specification follows Dan North's BDD principles, focusing on behavior rather than implementation, with clear Given-When-Then scenarios.

## Design Principles Applied

### 1. **Behavior Over Implementation**
- Tests describe *what* the system should do, not *how* it does it
- Focus on user scenarios and business outcomes
- Avoid testing internal implementation details

### 2. **Clear Given-When-Then Structure**
```ruby
# Example from the specs:
context "when report generation succeeds" do
  it "requests report generation and returns reference code" do
    # Given a valid query ID and successful API response
    expect(mock_http_client).to receive(:get)
      .with("/AccountManagement/FlexWebService/SendRequest", {
        t: flex_token,
        q: query_id,
        v: 3
      })
      .and_return(successful_generate_response)

    # When generating a report
    reference_code = flex_client.generate_report(query_id)

    # Then it should return the reference code for fetching
    expect(reference_code).to eq("1234567890123456")
  end
end
```

### 3. **Living Documentation**
- Test names clearly communicate expected behavior
- Scenarios read like specifications
- Context blocks organize related behaviors

### 4. **Comprehensive Error Coverage**
- Both happy path and error scenarios
- Specific error classes for different failure modes
- Helpful error messages and recovery suggestions

## Test Structure and Organization

### File Structure
```
spec/
├── lib/ibkr/
│   ├── flex_spec.rb                           # Core Flex client behavior
│   ├── services/flex_spec.rb                  # Service layer integration
│   ├── models/flex_report_spec.rb             # Data transformation
│   └── errors/flex_error_spec.rb              # Error handling
├── features/flex_report_generation_spec.rb    # End-to-end integration
├── fixtures/api_responses/flex/               # Test data
└── support/shared_examples/flex_behaviors.rb  # Reusable test patterns
```

### Test Levels

#### 1. **Unit Level** (`lib/ibkr/flex_spec.rb`)
- **Focus**: Core Flex client functionality
- **Scenarios**: 
  - Authentication and configuration
  - Report generation workflow
  - Report fetching workflow  
  - Parameter validation
  - Error handling for each operation
  - Thread safety and concurrency
  - Memory management

#### 2. **Service Integration** (`services/flex_spec.rb`)
- **Focus**: Integration with main IBKR client architecture
- **Scenarios**:
  - Service delegation patterns
  - Authentication requirements
  - Configuration management
  - Error propagation
  - Performance and caching

#### 3. **Feature Integration** (`features/flex_report_generation_spec.rb`)
- **Focus**: End-to-end user workflows
- **Scenarios**:
  - Complete report generation and retrieval
  - Integration with OAuth authentication
  - Multi-account support
  - Large report handling
  - Error recovery workflows

#### 4. **Data Models** (`models/flex_report_spec.rb`)
- **Focus**: Data transformation and access
- **Scenarios**:
  - XML to Ruby object transformation
  - Data validation and integrity
  - Aggregation and analysis methods
  - Export and serialization
  - Performance with large datasets

#### 5. **Error Handling** (`errors/flex_error_spec.rb`)
- **Focus**: Comprehensive error scenarios
- **Scenarios**:
  - Error hierarchy and inheritance
  - Context-specific error handling
  - Debugging information
  - Recovery suggestions

## Key BDD Scenarios Covered

### Core Workflow Scenarios

#### 1. **Successful Report Generation**
```ruby
scenario "successfully generates report and retrieves trading activity data" do
  # Given user has configured Flex Web Service token
  # And user has created a query in Client Portal with specific ID
  # And IBKR Flex Web Service responds successfully to generation request
  # When user initiates Flex report workflow through main client
  # And user generates report with their query ID
  # Then reference code should be returned for fetching
  # When user fetches the completed report
  # Then comprehensive trading data should be available
end
```

#### 2. **Report Generation with Polling**
```ruby
scenario "handles report generation with polling for completion" do
  # Given user initiates report generation
  # And initial fetch attempt returns "still processing"
  # And subsequent fetch succeeds
  # When user follows workflow with retry logic
  # Then final report should be successfully retrieved
end
```

### Error Scenarios

#### 3. **Invalid Query Handling**
```ruby
it "raises FlexError with descriptive message for query not found" do
  # Given query ID does not exist
  # When attempting to generate report with invalid query
  # Then it should raise a specific error with context
end
```

#### 4. **Network Resilience**
```ruby
it "handles network connectivity issues" do
  # Given network connection fails during generation
  # When user attempts report generation during network issues
  # Then network error should be raised with recovery guidance
end
```

### Integration Scenarios

#### 5. **OAuth + Flex Integration**
```ruby
scenario "combines OAuth authentication with Flex report access" do
  # Given user has authenticated main IBKR client
  # When user authenticates and sets up session
  # And user accesses Flex reports through authenticated client
  # Then both OAuth and Flex operations should work seamlessly
end
```

## Shared Examples and Reusable Patterns

### 1. **Flex Web Service Operation**
```ruby
RSpec.shared_examples "a Flex Web Service operation" do
  it "uses correct authentication token"
  it "targets correct IBKR Flex Web Service endpoint"
  it "includes required API version parameter"
end
```

### 2. **Error Handling Patterns**
```ruby
RSpec.shared_examples "a Flex error handler" do |error_class, error_code|
  it "raises specific error class for #{error_code}"
  it "includes error code in exception"
  it "provides relevant error context"
  it "includes helpful suggestions for recovery"
end
```

### 3. **Thread Safety Testing**
```ruby
RSpec.shared_examples "a Flex thread-safe operation" do
  it "supports concurrent access"
  it "maintains state consistency under concurrency"
  it "handles concurrent errors gracefully"
end
```

## Error Handling Strategy

### Error Hierarchy
```
Ibkr::BaseError
└── Ibkr::FlexError::Base
    ├── Ibkr::FlexError::ConfigurationError
    ├── Ibkr::FlexError::QueryNotFound
    ├── Ibkr::FlexError::ReportNotReady
    ├── Ibkr::FlexError::InvalidReference
    ├── Ibkr::FlexError::NetworkError
    ├── Ibkr::FlexError::ParseError
    └── Ibkr::FlexError::ApiError
```

### Error Context and Debugging
- **Rich Context**: Each error includes operation details, parameters, and timing
- **Recovery Suggestions**: Actionable guidance for error resolution
- **Debug Information**: Complete context for troubleshooting
- **Consistent Format**: All errors follow same structure for handling

## Test Data and Fixtures

### XML Response Fixtures
- `generate_success.xml`: Successful report generation response
- `generate_error.xml`: Error response (query not found)
- `fetch_success.xml`: Complete report with multiple data sections
- `fetch_error.xml`: Report not ready response

### Mock Strategies
- **HTTP Client Mocking**: Faraday responses mocked at appropriate level
- **Credential Mocking**: Rails credentials stubbed consistently
- **Response Variations**: Multiple response types for different scenarios
- **Error Injection**: Network and parsing errors simulated

## Performance and Scalability Testing

### Performance Scenarios
```ruby
RSpec.shared_examples "a Flex performance test" do |max_time: 1.0|
  it "completes operation within acceptable time"
  it "handles large responses efficiently"
  it "manages memory usage efficiently"
end
```

### Scalability Considerations
- **Large Reports**: Testing with 1000+ trade records
- **Concurrent Operations**: Multiple simultaneous requests
- **Memory Management**: Garbage collection verification
- **Response Processing**: XML parsing efficiency

## Integration with Existing Patterns

### Following Existing Gem Patterns
1. **Service Architecture**: Inherits from `Services::Base`
2. **Error Handling**: Uses established error hierarchy
3. **Configuration**: Integrates with `Ibkr::Configuration`
4. **HTTP Client**: Leverages existing HTTP patterns
5. **Model Structure**: Uses Dry::Struct patterns
6. **Testing Style**: Follows existing BDD approach

### Mocking Consistency
- **Rails Credentials**: Consistent mocking across all specs
- **HTTP Responses**: Proper Faraday response mocking
- **Error Scenarios**: Realistic error simulation
- **Threading**: Thread-safe test execution

## Recommended Implementation Structure

### Core Classes
```ruby
# lib/ibkr/flex.rb - Main Flex client
# lib/ibkr/services/flex.rb - Service layer
# lib/ibkr/models/flex_report.rb - Report model
# lib/ibkr/models/flex_trade.rb - Trade model
# lib/ibkr/errors/flex_error.rb - Error classes
```

### Integration Points
```ruby
# Add to Ibkr::Client
def flex
  @flex ||= Services::Flex.new(self)
end

# Add to Services module
module Services
  class Flex < Base
    # Implementation following established patterns
  end
end
```

## Benefits of This BDD Approach

### 1. **Clear Requirements**
- Tests serve as executable documentation
- Business behavior is clearly defined
- Edge cases are explicitly covered

### 2. **Maintainable Tests**
- Behavior-focused tests are less brittle
- Clear separation of concerns
- Reusable shared examples

### 3. **Comprehensive Coverage**
- Unit, integration, and feature levels
- Error scenarios well covered
- Performance considerations included

### 4. **Developer Confidence**
- Clear understanding of expected behavior
- Reliable safety net for refactoring
- Consistent error handling

### 5. **Integration Quality**
- Follows existing gem patterns
- Maintains architectural consistency
- Provides upgrade path for future enhancements

## Usage Examples

### Running the Test Suite
```bash
# Run all Flex-related tests
bundle exec rspec spec/lib/ibkr/flex_spec.rb
bundle exec rspec spec/lib/ibkr/services/flex_spec.rb
bundle exec rspec spec/features/flex_report_generation_spec.rb

# Run specific scenarios
bundle exec rspec spec/lib/ibkr/flex_spec.rb -t focus
bundle exec rspec spec/features/flex_report_generation_spec.rb --format documentation

# Run performance tests
bundle exec rspec spec/lib/ibkr/flex_spec.rb -t performance
```

### Test-Driven Development Flow
1. **Write failing scenarios** describing desired behavior
2. **Implement minimal code** to make tests pass
3. **Refactor implementation** while keeping tests green
4. **Add edge cases** and error scenarios
5. **Optimize performance** with performance tests as guards

This comprehensive BDD specification provides a solid foundation for implementing robust, well-tested Flex Web Service integration while maintaining the high quality standards of the existing IBKR Ruby gem.