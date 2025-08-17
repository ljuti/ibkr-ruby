# IBKR Gem Refactoring Plan

## Overview

This document outlines the refactoring roadmap for the IBKR Ruby gem based on comprehensive code analysis. The goal is to improve maintainability, extensibility, and performance while maintaining backward compatibility.

## Current State Assessment

### Strengths
- ✅ **Strong Foundation**: Excellent type safety with Dry::Struct models
- ✅ **Comprehensive OAuth**: Complete OAuth 1.0a implementation with RSA/HMAC signatures
- ✅ **Excellent Test Coverage**: 257 tests, 0 failures, 21 pending
- ✅ **Hybrid Account Management**: Single and multi-account workflows
- ✅ **Real API Integration**: Live IBKR API calls for account discovery
- ✅ **Proper Error Handling**: Comprehensive error hierarchy with repository-specific errors
- ✅ **Modern Architecture**: Fluent interfaces and repository pattern implemented
- ✅ **Flexible Data Access**: Multiple repository implementations (API, Cached, Test)

### Architecture Quality
- **Design Patterns**: Excellent - Repository and Factory patterns implemented
- **Code Organization**: Very good module structure with clear separation
- **Separation of Concerns**: Excellent - data access abstracted via repositories
- **Type Safety**: Excellent with Dry::Types
- **Extensibility**: Good - repository pattern enables easy feature additions
- **Developer Experience**: Excellent - fluent interfaces provide intuitive API

## Refactoring Roadmap

### Phase 1: Developer Experience Improvements (Immediate)
- [x] **Fluent Interfaces** - Chainable API methods for better usability ✅ 
- [x] **Enhanced Error Context** - Better error messages and debugging info ✅
- [ ] **API Documentation** - Improve inline documentation and examples

### Phase 2: Architectural Patterns (Short-term)
- [x] **Repository Pattern** - Abstract data access for better testing and flexibility ✅
- [x] **Factory Pattern** - Service creation and configuration management ✅
- [ ] **Strategy Pattern** - Pluggable authentication strategies
- [ ] **Observer Pattern** - Event-driven architecture for extensibility

### Phase 3: Performance Optimizations (Medium-term)
- [ ] **Connection Pooling** - Reuse HTTP connections for better performance
- [x] **Response Caching** - Cache API responses where appropriate ✅ (via CachedAccountRepository)
- [ ] **Lazy Loading** - Load services and data on-demand
- [ ] **Async Operations** - Non-blocking API calls for better throughput

### Phase 4: Extensibility & Plugin Architecture (Long-term)
- [ ] **Plugin System** - Modular architecture for new features
- [ ] **Configuration DSL** - Declarative configuration syntax
- [ ] **Event System** - Publish/subscribe for loose coupling
- [ ] **Service Registry** - Dynamic service discovery and registration

## Detailed Recommendations

### 1. Fluent Interfaces (Priority: High, Impact: High)

**Current State:**
```ruby
client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
client.authenticate
summary = client.accounts.summary
positions = client.accounts.positions
```

**Target State:**
```ruby
summary = Ibkr.client("DU123456")
  .authenticate
  .accounts
  .summary

positions = Ibkr.client("DU123456")
  .with_account("DU789012")
  .accounts
  .positions(page: 1, sort: "market_value")
```

**Implementation Plan:**
- Create `Ibkr` module-level factory methods
- Add chainable methods to `Client`
- Implement fluent account switching
- Maintain backward compatibility

### 2. Repository Pattern (Priority: Medium, Impact: High) ✅ COMPLETED

**Implemented Architecture:**
```ruby
# Repository interface contract
module AccountRepositoryInterface
  def find_summary(account_id)
  def find_metadata(account_id)
  def find_positions(account_id, options = {})
  def find_transactions(account_id, contract_id, days)
  def discover_accounts()
end

# Multiple implementations with automatic selection
class ApiAccountRepository < BaseRepository          # Direct API calls
class CachedAccountRepository < BaseRepository      # API + caching layer
class TestAccountRepository < BaseRepository        # In-memory test data

# Factory with intelligent auto-detection
RepositoryFactory.create_auto_repository(client)
# -> :cached for sandbox, :api for live trading, :test for testing
```

**Implementation Features:**
- ✅ Abstract interface with clear contracts
- ✅ Three repository implementations (API, Cached, Test)
- ✅ Intelligent factory with auto-detection
- ✅ Configurable cache TTL settings
- ✅ Comprehensive error handling
- ✅ 100% backward compatibility maintained
- ✅ Integration with Services layer

**Benefits Achieved:**
- Better testing with TestAccountRepository
- Automatic caching with configurable TTL
- Clean separation of data access
- Easy to add new repository types
- Performance improvements with intelligent caching

### 3. Strategy Pattern for Authentication (Priority: Medium, Impact: Medium)

**Target Architecture:**
```ruby
# Multiple authentication strategies
class OAuthStrategy
class ApiKeyStrategy  # Future
class CertificateStrategy  # Future

# Configurable authentication
client = Ibkr::Client.new(
  auth_strategy: OAuthStrategy.new(config),
  account_id: "DU123456"
)
```

### 4. Enhanced Error Context (Priority: High, Impact: Medium) ✅ COMPLETED

**Implemented Features:**
```ruby
# Rich contextual errors with actionable information
error = Ibkr::ApiError.account_not_found("DU999999", context: {
  available_accounts: ["DU123456", "DU789012"],
  operation: "set_active_account"
})

# Enhanced error information
puts error.detailed_message
# => Account DU999999 not found or not accessible
#    Endpoint: /v1/api/portfolio/DU999999/summary
#    Account: DU999999
#    
#    Suggestions:
#      - Use client.available_accounts to see available account IDs
#      - Ensure the account is valid and accessible

# Debug information for troubleshooting
error.debug_info
# => { error_class: "Ibkr::ApiError::NotFound", timestamp: "2025-08-17T12:22:55+03:00",
#      http_status: 404, request_id: "req-12345", endpoint: "/v1/api/portfolio/DU999999/summary" }
```

**Implementation Features:**
- ✅ Automatic context capture (timestamp, thread ID, IBKR version, caller location)
- ✅ Intelligent suggestion system based on error type and context
- ✅ Comprehensive debug information for troubleshooting
- ✅ Rich error factory methods with contextual information
- ✅ HTTP integration with request/response context
- ✅ Enhanced serialization for logging and monitoring
- ✅ 100% backward compatibility maintained

**Benefits Achieved:**
- Significantly improved debugging capabilities
- Actionable guidance for resolving common issues
- Rich contextual information for API integration troubleshooting
- Better error reporting and monitoring in production

### 5. Connection Pooling (Priority: Medium, Impact: High)

**Implementation:**
- Configure Faraday connection pooling
- Implement connection lifecycle management
- Add connection health checks
- Optimize for concurrent requests

### 6. Plugin Architecture (Priority: Low, Impact: High)

**Target Structure:**
```ruby
# Plugin registration
Ibkr.register_plugin(:market_data, MarketDataPlugin)
Ibkr.register_plugin(:order_management, OrderPlugin)

# Plugin usage
client = Ibkr.client("DU123456")
  .with_plugin(:market_data)
  .with_plugin(:order_management)
```

## Implementation Priority Matrix

| Feature | Priority | Impact | Effort | Status | Dependencies |
|---------|----------|--------|--------|---------|--------------|
| ~~Fluent Interfaces~~ | ~~High~~ | ~~High~~ | ~~Low~~ | ✅ **DONE** | ~~None~~ |
| ~~Enhanced Errors~~ | ~~High~~ | ~~Medium~~ | ~~Low~~ | ✅ **DONE** | ~~None~~ |
| ~~Repository Pattern~~ | ~~Medium~~ | ~~High~~ | ~~Medium~~ | ✅ **DONE** | ~~None~~ |
| Connection Pooling | Medium | High | Low | 📋 Planned | None |
| Strategy Pattern | Medium | Medium | Medium | 📋 Planned | Repository ✅ |
| Plugin Architecture | Low | High | High | 📋 Future | Strategy, Repository ✅ |

## Backward Compatibility Strategy

All refactoring will maintain 100% backward compatibility by:

1. **Additive Changes**: New interfaces alongside existing ones
2. **Deprecation Warnings**: Clear migration paths for deprecated features
3. **Alias Methods**: Maintain old method names as aliases
4. **Configuration Flags**: Feature flags for new behavior
5. **Documentation**: Clear migration guides and examples

## Testing Strategy

Each refactoring phase will include:

1. **Unit Tests**: Comprehensive test coverage for new patterns
2. **Integration Tests**: End-to-end testing with real API calls
3. **Regression Tests**: Ensure existing functionality unchanged
4. **Performance Tests**: Benchmark improvements and monitor regressions
5. **Documentation Tests**: Verify all examples work correctly

## Success Metrics

- **Developer Experience**: Reduced lines of code for common operations
- **Maintainability**: Lower cyclomatic complexity, better test coverage
- **Performance**: Faster response times, reduced memory usage
- **Extensibility**: Easy addition of new features and plugins
- **Reliability**: Fewer bugs, better error handling and recovery

## Implementation Status

### Completed ✅

#### 1. Refactoring Plan Documentation
- Comprehensive roadmap with priority matrix
- Regular updates tracking implementation progress
- Success metrics and testing strategy defined

#### 2. Fluent Interfaces (Phase 1)
- ✅ Complete implementation with 26 passing tests
- ✅ Module-level factory methods (`Ibkr.client`, `Ibkr.connect`, etc.)
- ✅ Chainable client methods (`authenticate!`, `with_account`)
- ✅ ChainableAccountsProxy for fluent account operations
- ✅ Comprehensive test coverage and documentation
- ✅ 100% backward compatibility maintained

#### 3. Repository Pattern (Phase 2)
- ✅ Complete implementation with all tests passing
- ✅ AccountRepositoryInterface defining clear contracts
- ✅ Three repository implementations:
  - `ApiAccountRepository` - Direct IBKR API calls
  - `CachedAccountRepository` - API calls with intelligent caching
  - `TestAccountRepository` - In-memory test data
- ✅ RepositoryFactory with auto-detection logic
- ✅ Configuration integration for cache TTL settings
- ✅ Comprehensive error handling with RepositoryError class
- ✅ Services layer integration maintaining backward compatibility
- ✅ Performance improvements through intelligent caching

#### 4. Factory Pattern (Phase 2)
- ✅ RepositoryFactory with multiple creation strategies
- ✅ Auto-detection based on environment and configuration
- ✅ Support for repository chains and custom configurations

#### 5. Enhanced Error Context (Phase 1)
- ✅ Complete implementation with 22 passing tests
- ✅ Rich context capture (timestamp, thread ID, version, caller location)
- ✅ Intelligent suggestion system for common issues
- ✅ Comprehensive debug information for troubleshooting
- ✅ Enhanced error factory methods with contextual information
- ✅ HTTP integration with request/response context
- ✅ Defensive error handling for compatibility with existing tests
- ✅ 100% backward compatibility maintained

### In Progress 🟡
*None currently*

### Next Steps 📋

1. ✅ Document refactoring plan
2. ✅ Implement fluent interfaces (Phase 1)
3. ✅ Repository pattern implementation (Phase 2)
4. ✅ Enhanced error context (Phase 1)
5. 🔜 Connection pooling (Phase 3) - **NEXT PRIORITY**
6. 📋 Strategy pattern for authentication (Phase 2)
7. 📋 Performance optimizations (Phase 3)

### Success Metrics Achieved ✅
- **Developer Experience**: Fluent API reduces boilerplate code significantly
- **Maintainability**: Repository pattern provides clean separation of concerns
- **Performance**: Intelligent caching reduces API calls in sandbox mode
- **Extensibility**: Easy to add new repository types and authentication strategies
- **Reliability**: Enhanced error handling with contextual debugging and 257 passing tests
- **Test Coverage**: 100% backward compatibility with improved testing capabilities

## Available Features & Usage

With the completed refactoring, developers can now leverage:

### Fluent Interface API
```ruby
# Single-account workflow
summary = Ibkr.connect("DU123456", live: false).portfolio.summary

# Multi-account workflow with switching
positions = Ibkr.connect(live: false)
  .with_account("DU789012")
  .portfolio
  .sorted_by("market_value", "desc")
  .with_page(1)
  .positions
```

### Repository Pattern Features
```ruby
# Automatic repository selection
client = Ibkr::Client.new(live: false)  # Uses CachedAccountRepository
client = Ibkr::Client.new(live: true)   # Uses ApiAccountRepository

# Explicit repository configuration
client.config.repository_type = :test   # Uses TestAccountRepository

# Custom cache TTL settings
client.config.cache_ttl = {
  summary: 60,      # Cache summary for 60 seconds
  positions: 30,    # Cache positions for 30 seconds
  metadata: 300     # Cache metadata for 5 minutes
}
```

### Testing Improvements
```ruby
# Use test repository for reliable testing
ENV["IBKR_USE_TEST_REPOSITORY"] = "true"
client = Ibkr::Client.new

# Or inject test repository directly
test_repo = Ibkr::Repositories::TestAccountRepository.new(client)
service = Ibkr::Services::Accounts.new(client, repository: test_repo)
```

### Enhanced Error Context Features
```ruby
# Rich error context with actionable suggestions
begin
  client.set_active_account("INVALID_ACCOUNT")
rescue Ibkr::ApiError::NotFound => error
  puts error.detailed_message
  # => Account INVALID_ACCOUNT not found or not accessible
  #    Account: INVALID_ACCOUNT
  #    
  #    Suggestions:
  #      - Use client.available_accounts to see available account IDs
  #      - Ensure the account is valid and accessible
  
  # Access debug information for troubleshooting
  puts error.debug_info
  # => { error_class: "Ibkr::ApiError::NotFound", timestamp: "2025-08-17T12:22:55+03:00" }
  
  # Get structured context for logging
  puts error.to_h
  # => { error: "Ibkr::ApiError::NotFound", message: "...", context: {...}, suggestions: [...] }
end

# Enhanced authentication errors
begin
  client.authenticate
rescue Ibkr::AuthenticationError::InvalidCredentials => error
  puts error.suggestions
  # => ["Verify your OAuth credentials are correct", "Check if your session has expired", ...]
end
```

This refactoring plan will continue to be updated as work progresses and new requirements emerge. The foundation patterns (Repository, Factory, Fluent Interfaces, Enhanced Error Context) are now in place, providing a solid base for future enhancements.