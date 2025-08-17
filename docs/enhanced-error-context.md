# Enhanced Error Context Guide

## Overview

The IBKR Ruby gem provides enhanced error context to make debugging and troubleshooting API integration issues significantly easier. Instead of basic error messages, you get rich contextual information, actionable suggestions, and comprehensive debug data.

## Table of Contents

- [Quick Start](#quick-start)
- [Core Features](#core-features)
- [Error Types](#error-types)
- [Context Information](#context-information)
- [Suggestions System](#suggestions-system)
- [Debug Information](#debug-information)
- [Factory Methods](#factory-methods)
- [Logging and Monitoring](#logging-and-monitoring)
- [Best Practices](#best-practices)
- [Troubleshooting Guide](#troubleshooting-guide)

## Quick Start

### Basic Error Handling

```ruby
require 'ibkr'

client = Ibkr::Client.new(default_account_id: "DU123456", live: false)

begin
  client.set_active_account("INVALID_ACCOUNT")
rescue Ibkr::ApiError => error
  # Basic error message
  puts error.message
  # => "Account INVALID_ACCOUNT not found or not accessible"
  
  # Enhanced detailed message with context and suggestions
  puts error.detailed_message
  # => Account INVALID_ACCOUNT not found or not accessible
  #    Account: INVALID_ACCOUNT
  #    
  #    Suggestions:
  #      - Use client.available_accounts to see available account IDs
  #      - Ensure the account is valid and accessible
end
```

### Getting Debug Information

```ruby
begin
  response = client.get("/v1/api/portfolio/INVALID/summary")
rescue Ibkr::ApiError => error
  debug_info = error.debug_info
  puts debug_info
  # => {
  #      error_class: "Ibkr::ApiError::NotFound",
  #      timestamp: "2025-08-17T12:22:55+03:00",
  #      http_status: 404,
  #      request_id: "req-abc123",
  #      endpoint: "/v1/api/portfolio/INVALID/summary",
  #      user_agent: "IBKR Ruby Client 1.0.0"
  #    }
end
```

## Core Features

### 1. Automatic Context Capture

Every error automatically captures:

- **Timestamp**: When the error occurred (ISO 8601 format)
- **Thread ID**: For multi-threaded debugging
- **IBKR Version**: The gem version for compatibility checks
- **Caller Location**: Stack trace information (filtered for relevance)

```ruby
error.context
# => {
#      timestamp: "2025-08-17T12:22:55+03:00",
#      thread_id: 70123456789,
#      ibkr_version: "1.0.0",
#      caller_location: ["lib/my_app.rb:42:in `fetch_data'", ...]
#    }
```

### 2. HTTP Request Context

For API-related errors, additional HTTP context is captured:

- **Endpoint**: The API endpoint that failed
- **HTTP Method**: GET, POST, PUT, DELETE
- **Response Status**: HTTP status code
- **Request ID**: For tracking requests with IBKR support
- **User Agent**: Client identification
- **Response Time**: How long the request took

```ruby
error.context
# => {
#      endpoint: "/v1/api/iserver/accounts",
#      method: "GET",
#      response_status: 401,
#      request_id: "req-def456",
#      user_agent: "IBKR Ruby Client 1.0.0",
#      response_time: 1.23
#    }
```

### 3. Operation Context

Errors include information about what operation was being performed:

```ruby
error.context
# => {
#      operation: "set_active_account",
#      account_id: "DU123456",
#      available_accounts: ["DU123456", "DU789012"],
#      retry_count: 2
#    }
```

## Error Types

### Authentication Errors

```ruby
# Invalid credentials
begin
  client.authenticate
rescue Ibkr::AuthenticationError::InvalidCredentials => error
  puts error.suggestions
  # => ["Verify your OAuth credentials are correct",
  #     "Check if your session has expired",
  #     "Ensure your system clock is synchronized"]
end

# Token expired
begin
  client.get("/protected/endpoint")
rescue Ibkr::AuthenticationError::TokenExpired => error
  puts error.context[:operation]  # => "token_validation"
  puts error.suggestions
  # => ["Verify your OAuth credentials are correct", ...]
end

# Session initialization failed
begin
  client.authenticate
rescue Ibkr::AuthenticationError::SessionInitializationFailed => error
  puts error.context[:operation]  # => "session_init"
end
```

### API Errors

```ruby
# Account not found
begin
  client.set_active_account("INVALID")
rescue Ibkr::ApiError::NotFound => error
  puts error.context[:account_id]           # => "INVALID"
  puts error.context[:operation]            # => "set_active_account"
  puts error.context[:available_accounts]   # => ["DU123456", "DU789012"]
end

# Validation errors
begin
  # Some API call with invalid data
rescue Ibkr::ApiError::ValidationError => error
  puts error.validation_errors
  # => [{"field" => "amount", "error" => "must be positive"}]
  puts error.context[:operation]  # => "request_validation"
end

# Server errors
begin
  client.get("/some/endpoint")
rescue Ibkr::ApiError::ServerError => error
  puts error.context[:http_status]    # => 500
  puts error.context[:request_id]     # => "req-xyz789"
end
```

### Repository Errors

```ruby
# Unsupported repository type
begin
  Ibkr::Repositories::RepositoryFactory.create_account_repository(
    client, 
    type: :invalid_type
  )
rescue Ibkr::RepositoryError => error
  puts error.context[:repository_type]     # => :invalid_type
  puts error.context[:available_types]     # => [:api, :cached, :test]
  puts error.context[:operation]           # => "factory_creation"
end

# Data not found in repository
begin
  repo.find_summary("INVALID_ACCOUNT")
rescue Ibkr::RepositoryError => error
  puts error.context[:resource]      # => "Account"
  puts error.context[:identifier]    # => "INVALID_ACCOUNT"
  puts error.context[:operation]     # => "data_retrieval"
end
```

### Rate Limit Errors

```ruby
begin
  # Make too many requests
rescue Ibkr::RateLimitError => error
  puts error.suggestions
  # => ["Implement exponential backoff in your retry logic",
  #     "Reduce the frequency of API calls",
  #     "Consider caching responses to minimize API usage"]
  
  puts error.context[:retry_after]  # => "60" (seconds to wait)
end
```

## Context Information

### Available Context Fields

| Field | Description | Example |
|-------|-------------|---------|
| `timestamp` | When the error occurred | `"2025-08-17T12:22:55+03:00"` |
| `thread_id` | Thread identifier | `70123456789` |
| `ibkr_version` | Gem version | `"1.0.0"` |
| `caller_location` | Stack trace (filtered) | `["lib/my_app.rb:42:in 'fetch_data'"]` |
| `endpoint` | API endpoint | `"/v1/api/iserver/accounts"` |
| `method` | HTTP method | `"GET"` |
| `response_status` | HTTP status code | `404` |
| `request_id` | IBKR request ID | `"req-abc123"` |
| `user_agent` | Client user agent | `"IBKR Ruby Client 1.0.0"` |
| `operation` | What was being done | `"set_active_account"` |
| `account_id` | Account involved | `"DU123456"` |
| `available_accounts` | Available accounts | `["DU123456", "DU789012"]` |
| `retry_count` | How many retries | `3` |

## Suggestions System

The suggestion system provides context-aware guidance based on the error type and situation:

### Authentication Suggestions

```ruby
error.suggestions
# => ["Verify your OAuth credentials are correct",
#     "Check if your session has expired", 
#     "Ensure your system clock is synchronized"]
```

### Account Management Suggestions

```ruby
# When account not found
error.suggestions
# => ["Use client.available_accounts to see available account IDs",
#     "Ensure the account is valid and accessible"]

# When account ID is empty
error.suggestions
# => ["Provide a valid account ID",
#     "Use client.available_accounts to see available account IDs"]
```

### Endpoint-Specific Suggestions

```ruby
# For /iserver/accounts endpoint
error.suggestions
# => ["Ensure you're authenticated before fetching accounts",
#     "Verify your account has proper permissions"]

# For portfolio endpoints
error.suggestions
# => ["Check that the account ID is valid and accessible",
#     "Ensure the account has positions or data to retrieve"]
```

### Rate Limiting Suggestions

```ruby
error.suggestions
# => ["Implement exponential backoff in your retry logic",
#     "Reduce the frequency of API calls",
#     "Consider caching responses to minimize API usage"]
```

### Repository Suggestions

```ruby
error.suggestions
# => ["Check if the repository type is supported",
#     "Verify the underlying data source is accessible",
#     "Try switching to a different repository implementation"]
```

## Debug Information

The `debug_info` method provides structured debugging information:

```ruby
error.debug_info
# => {
#      error_class: "Ibkr::ApiError::NotFound",
#      timestamp: "2025-08-17T12:22:55+03:00",
#      http_status: 404,
#      response_headers: {
#        "content-type" => "application/json",
#        "x-request-id" => "req-abc123"
#      },
#      request_id: "req-abc123",
#      endpoint: "/v1/api/portfolio/INVALID/summary",
#      retry_count: 2
#    }
```

## Factory Methods

Enhanced error classes provide factory methods for creating contextual errors:

### Authentication Error Factories

```ruby
# Invalid credentials with context
error = Ibkr::AuthenticationError.credentials_invalid(
  "Custom message",
  context: { username: "user@example.com", attempt: 3 }
)

# Session failed with context
error = Ibkr::AuthenticationError.session_failed(
  "Session init failed",
  context: { account_id: "DU123456", timeout: 30 }
)

# Token expired with context
error = Ibkr::AuthenticationError.token_expired(
  "Token expired",
  context: { token_age: 3600, issued_at: Time.now - 3600 }
)
```

### API Error Factories

```ruby
# Account not found with context
error = Ibkr::ApiError.account_not_found(
  "DU999999",
  context: { 
    available_accounts: ["DU123456", "DU789012"],
    operation: "portfolio_fetch"
  }
)

# Validation failed with context
error = Ibkr::ApiError.validation_failed(
  [{"field" => "amount", "error" => "must be positive"}],
  context: { request_type: "order", user_id: "user123" }
)

# Server error with context
error = Ibkr::ApiError.server_error(
  "Database connection failed",
  context: { server_id: "web-01", load: 0.85 }
)
```

### Repository Error Factories

```ruby
# Unsupported repository type
error = Ibkr::RepositoryError.unsupported_repository_type(
  "custom",
  context: { client_type: "test", environment: "development" }
)

# Data not found
error = Ibkr::RepositoryError.data_not_found(
  "Account",
  "DU999999", 
  context: { repository_type: "cached", cache_size: 100 }
)
```

## Logging and Monitoring

### Structured Logging

```ruby
require 'json'
require 'logger'

logger = Logger.new(STDOUT)

begin
  client.authenticate
rescue Ibkr::BaseError => error
  # Log structured error information
  log_data = {
    level: "ERROR",
    timestamp: Time.now.iso8601,
    error: error.to_h,
    user_id: current_user&.id,
    session_id: session.id
  }
  
  logger.error(JSON.generate(log_data))
end
```

### Error Monitoring Integration

```ruby
# Sentry integration example
begin
  client.get("/some/endpoint")
rescue Ibkr::BaseError => error
  Sentry.capture_exception(error, extra: {
    error_context: error.context,
    suggestions: error.suggestions,
    debug_info: error.debug_info
  })
  
  # Re-raise or handle as needed
  raise
end

# Custom monitoring
begin
  client.authenticate
rescue Ibkr::AuthenticationError => error
  ErrorTracker.track(
    error_class: error.class.name,
    message: error.message,
    context: error.context,
    suggestions: error.suggestions,
    user_id: current_user.id
  )
end
```

### Performance Monitoring

```ruby
begin
  start_time = Time.now
  response = client.get("/expensive/endpoint")
rescue Ibkr::BaseError => error
  duration = Time.now - start_time
  
  PerformanceMonitor.record_error(
    endpoint: error.context[:endpoint],
    duration: duration,
    error_type: error.class.name,
    http_status: error.context[:response_status],
    request_id: error.context[:request_id]
  )
end
```

## Best Practices

### 1. Always Use Detailed Messages for User Feedback

```ruby
begin
  client.set_active_account(params[:account_id])
rescue Ibkr::ApiError::NotFound => error
  # Good: Use detailed message for user feedback
  flash[:error] = error.detailed_message
  
  # Log technical details
  logger.error("Account switch failed", error.debug_info)
end
```

### 2. Implement Retry Logic with Context

```ruby
MAX_RETRIES = 3

def authenticate_with_retry
  retries = 0
  
  begin
    client.authenticate
  rescue Ibkr::RateLimitError => error
    retries += 1
    
    if retries <= MAX_RETRIES
      # Use suggestions to implement proper retry logic
      if error.suggestions.any? { |s| s.include?("exponential backoff") }
        sleep(2 ** retries)  # Exponential backoff
      end
      
      retry
    else
      logger.error("Max retries exceeded", error.debug_info)
      raise
    end
  end
end
```

### 3. Create Rich Error Context in Your Code

```ruby
def fetch_account_data(account_id)
  begin
    client.accounts.summary
  rescue Ibkr::BaseError => error
    # Add your application context
    enhanced_error = error.class.with_context(
      error.message,
      context: error.context.merge(
        user_id: current_user.id,
        feature: "account_dashboard",
        requested_account: account_id
      )
    )
    
    raise enhanced_error
  end
end
```

### 4. Use Context for Conditional Error Handling

```ruby
begin
  client.authenticate
rescue Ibkr::AuthenticationError => error
  case error.context[:operation]
  when "session_init"
    # Handle session initialization failures
    redirect_to login_path, alert: "Session setup failed. Please try again."
  when "token_validation"
    # Handle token validation failures
    refresh_token_and_retry
  else
    # Handle general authentication failures
    redirect_to login_path, alert: error.detailed_message
  end
end
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Authentication Problems

**Error**: `Ibkr::AuthenticationError::InvalidCredentials`

**Check**:
```ruby
error.suggestions
# Look for specific guidance like:
# - "Verify your OAuth credentials are correct"
# - "Check if your session has expired"
# - "Ensure your system clock is synchronized"

error.context[:auth_header_present]  # Check if auth header was sent
error.context[:endpoint]             # Check which endpoint failed
```

**Solutions**:
- Verify OAuth credentials in configuration
- Check system clock synchronization
- Ensure tokens haven't expired
- Verify IBKR account permissions

#### 2. Account Access Issues

**Error**: `Ibkr::ApiError::NotFound`

**Check**:
```ruby
error.context[:account_id]           # Which account was requested
error.context[:available_accounts]   # What accounts are available  
error.context[:operation]            # What operation was attempted
```

**Solutions**:
- Use `client.available_accounts` to see valid accounts
- Verify account permissions
- Check if account is active in IBKR

#### 3. Rate Limiting

**Error**: `Ibkr::RateLimitError`

**Check**:
```ruby
error.context[:retry_after]  # How long to wait
error.suggestions           # Specific retry guidance
```

**Solutions**:
- Implement exponential backoff
- Reduce request frequency
- Use caching to minimize API calls
- Consider using CachedAccountRepository

#### 4. Repository Issues

**Error**: `Ibkr::RepositoryError`

**Check**:
```ruby
error.context[:repository_type]    # Which repository type
error.context[:operation]          # What was being attempted
error.context[:available_types]    # What types are supported
```

**Solutions**:
- Switch repository type: `client.config.repository_type = :api`
- Check repository configuration
- Verify test data setup for TestAccountRepository

### Debugging Workflows

#### 1. API Integration Issues

```ruby
# Enable detailed error logging
def debug_api_call(endpoint)
  begin
    response = client.get(endpoint)
    logger.info("API Success", {
      endpoint: endpoint,
      status: response.status,
      response_time: Time.now
    })
    response
  rescue Ibkr::BaseError => error
    logger.error("API Failure", {
      endpoint: endpoint,
      error_class: error.class.name,
      context: error.context,
      suggestions: error.suggestions,
      debug_info: error.debug_info
    })
    raise
  end
end
```

#### 2. Authentication Flow Debugging

```ruby
def debug_authentication
  begin
    puts "Starting authentication..."
    puts "Config: #{client.config.validate!}"
    
    client.authenticate
    puts "Authentication successful"
    puts "Available accounts: #{client.available_accounts}"
    
  rescue Ibkr::AuthenticationError => error
    puts "Authentication failed:"
    puts "  Error: #{error.class.name}"
    puts "  Message: #{error.message}"
    puts "  Context: #{error.context}"
    puts "  Suggestions:"
    error.suggestions.each { |s| puts "    - #{s}" }
    puts "  Debug Info: #{error.debug_info}"
  end
end
```

#### 3. Performance Issue Investigation

```ruby
def analyze_performance_issues
  start_time = Time.now
  
  begin
    result = client.accounts.positions
    duration = Time.now - start_time
    
    if duration > 5.0  # Slow response
      logger.warn("Slow API response", {
        endpoint: "/positions",
        duration: duration,
        suggestion: "Consider using CachedAccountRepository"
      })
    end
    
    result
  rescue Ibkr::BaseError => error
    duration = Time.now - start_time
    
    logger.error("Performance issue during error", {
      duration: duration,
      error_context: error.context,
      debug_info: error.debug_info
    })
    
    raise
  end
end
```

## Advanced Usage

### Custom Error Context

```ruby
# Add custom context to any error
begin
  risky_operation()
rescue Ibkr::BaseError => error
  # Enhance error with application-specific context
  enhanced_error = error.class.with_context(
    error.message,
    context: error.context.merge(
      user_id: current_user.id,
      feature: "portfolio_analysis",
      market_conditions: get_market_status(),
      application_version: MyApp::VERSION
    )
  )
  
  raise enhanced_error
end
```

### Error Context Middleware

```ruby
class ErrorContextMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    @app.call(env)
  rescue Ibkr::BaseError => error
    # Add request context to IBKR errors
    enhanced_error = error.class.with_context(
      error.message,
      context: error.context.merge(
        request_id: env['HTTP_X_REQUEST_ID'],
        user_agent: env['HTTP_USER_AGENT'],
        remote_ip: env['REMOTE_ADDR'],
        request_path: env['REQUEST_PATH']
      )
    )
    
    raise enhanced_error
  end
end
```

The Enhanced Error Context system transforms debugging from guesswork into a systematic process, providing the information and guidance needed to quickly resolve issues and build robust IBKR integrations.