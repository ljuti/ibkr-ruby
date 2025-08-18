# IBKR Flex Web Service Examples

This guide provides comprehensive examples for using the IBKR Flex Web Service through the Ruby gem.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Basic Setup](#basic-setup)
3. [Simple Report Generation](#simple-report-generation)
4. [Advanced Report Handling](#advanced-report-handling)
5. [Working with Different Report Types](#working-with-different-report-types)
6. [Error Handling Patterns](#error-handling-patterns)
7. [Production Best Practices](#production-best-practices)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

Before using the Flex Web Service, you need:

1. **Flex Token**: Generate this in IBKR Client Portal under Settings → Account Settings → Flex Web Service
2. **Query IDs**: Create Flex Queries in Client Portal under Settings → Account Settings → Flex Queries
3. **Proper Configuration**: Set up your token in the gem configuration

## Basic Setup

### Configuration Options

```ruby
# Option 1: Environment Variable
ENV['IBKR_FLEX_TOKEN'] = 'your_flex_token_here'

# Option 2: Ruby Configuration
Ibkr.configure do |config|
  config.flex_token = 'your_flex_token_here'
  config.environment = :production  # or :sandbox
  config.timeout = 30               # HTTP timeout in seconds
end

# Option 3: Rails Credentials
# In config/credentials.yml.enc:
# ibkr:
#   flex:
#     token: your_flex_token_here

# Option 4: Direct Initialization
flex_client = Ibkr::Flex.new(token: 'your_flex_token_here')
```

### Client Initialization

```ruby
# With IBKR Client
client = Ibkr::Client.new(default_account_id: "DU123456")
flex = client.flex

# Standalone Flex Client
flex = Ibkr::Flex.new(token: ENV['IBKR_FLEX_TOKEN'])

# Check if Flex is available
if client.flex.available?
  puts "Flex service is configured and ready"
else
  puts "Flex token not configured"
end
```

## Simple Report Generation

### Basic Usage - Generate and Fetch

```ruby
# The simplest way to get a report
query_id = "123456"  # Your Query ID from Client Portal
report = client.flex.generate_and_fetch(query_id)

# Access the data
puts "Report Type: #{report[:type]}"
puts "Query Name: #{report[:query_name]}"
puts "Accounts: #{report[:accounts].join(', ')}"
```

### Working with Report Data

```ruby
# Generate and fetch a comprehensive portfolio report
report = client.flex.generate_and_fetch(query_id)

# Transactions
if report[:transactions]
  puts "\nTransactions (#{report[:transactions].size} total):"
  report[:transactions].each do |tx|
    puts "  #{tx[:trade_date]}: #{tx[:symbol]} - #{tx[:quantity]} @ $#{tx[:price]}"
    puts "    Proceeds: $#{tx[:proceeds]}, Commission: $#{tx[:commission]}"
  end
end

# Positions
if report[:positions]
  puts "\nPositions (#{report[:positions].size} total):"
  report[:positions].each do |pos|
    puts "  #{pos[:symbol]}: #{pos[:position]} shares"
    puts "    Market Value: $#{pos[:market_value]}"
    puts "    Unrealized P&L: $#{pos[:unrealized_pnl]}"
  end
end

# Cash Report
if report[:cash_report]
  puts "\nCash Balances:"
  report[:cash_report].each do |cash|
    puts "  #{cash[:currency]}: $#{cash[:ending_cash]}"
    puts "    Change: $#{cash[:ending_cash] - cash[:starting_cash]}"
  end
end

# Performance
if report[:performance]
  puts "\nPerformance:"
  report[:performance].each do |perf|
    puts "  Period: #{perf[:period]}"
    puts "  Realized P&L: $#{perf[:realized_pnl]}"
  end
end
```

## Advanced Report Handling

### Two-Step Process (Generate then Fetch)

```ruby
# Step 1: Generate the report (returns reference code)
reference_code = client.flex.generate_report(query_id)
puts "Report generation initiated. Reference: #{reference_code}"

# Step 2: Fetch the report (can be called multiple times)
begin
  report = client.flex.get_report(reference_code)
  puts "Report ready!"
rescue Ibkr::FlexError::ReportNotReady => e
  puts "Report still generating. Retry in #{e.retry_after} seconds."
  sleep(e.retry_after)
  retry
end
```

### Custom Polling Logic

```ruby
# Manual polling with custom intervals
def fetch_report_with_retry(flex, query_id, max_attempts: 12, interval: 5)
  reference_code = flex.generate_report(query_id)
  puts "Generated reference: #{reference_code}"
  
  attempts = 0
  while attempts < max_attempts
    begin
      report = flex.get_report(reference_code)
      puts "Report fetched successfully after #{attempts + 1} attempts"
      return report
    rescue Ibkr::FlexError::ReportNotReady => e
      attempts += 1
      puts "Attempt #{attempts}/#{max_attempts}: Report not ready, waiting #{interval}s..."
      sleep(interval)
    rescue Ibkr::FlexError::InvalidReference => e
      puts "Reference expired. Generating new report..."
      reference_code = flex.generate_report(query_id)
      attempts = 0  # Reset counter for new reference
    end
  end
  
  raise "Report not ready after #{max_attempts} attempts"
end

# Usage
report = fetch_report_with_retry(client.flex, "123456")
```

### Different Output Formats

```ruby
# Get report as parsed hash (default)
hash_report = client.flex.get_report(reference_code, format: :hash)
puts hash_report[:transactions].first

# Get report as FlexReport model with convenience methods
model_report = client.flex.get_report(reference_code, format: :model)
puts "Trades: #{model_report.trades.size}"
puts "First position: #{model_report.positions.first[:symbol]}"
puts "Cash balance: #{model_report.cash_reports.first[:ending_cash]}"

# Get raw XML for custom parsing
xml_report = client.flex.get_report(reference_code, format: :raw)
puts "Raw XML size: #{xml_report.length} bytes"

# Parse XML manually if needed
require 'ox'
doc = Ox.parse(xml_report)
```

## Working with Different Report Types

### Transaction Reports

```ruby
# Get detailed transaction history
transactions = client.flex.transactions_report(query_id)

transactions.each do |tx|
  puts "Transaction #{tx.transaction_id}:"
  puts "  Symbol: #{tx.symbol}"
  puts "  Date: #{tx.trade_date}"
  puts "  Quantity: #{tx.quantity}"
  puts "  Price: $#{tx.price}"
  puts "  Net Amount: $#{tx.net_amount}"
  puts "  Type: #{tx.stock? ? 'Stock' : 'Option'}"
end

# Filter and analyze transactions
aapl_transactions = transactions.select { |tx| tx.symbol == "AAPL" }
total_aapl_proceeds = aapl_transactions.sum(&:proceeds)
puts "Total AAPL proceeds: $#{total_aapl_proceeds}"

# Group by symbol
by_symbol = transactions.group_by(&:symbol)
by_symbol.each do |symbol, txs|
  total = txs.sum(&:net_amount)
  puts "#{symbol}: #{txs.size} trades, total: $#{total}"
end
```

### Position Reports

```ruby
# Get current positions
positions = client.flex.positions_report(query_id)

# Sort by market value
top_positions = positions.sort_by { |p| -p.market_value }.first(10)

puts "Top 10 Positions by Market Value:"
top_positions.each_with_index do |pos, i|
  puts "#{i+1}. #{pos.symbol}:"
  puts "   Shares: #{pos.position}"
  puts "   Market Value: $#{pos.market_value}"
  puts "   Unrealized P&L: $#{pos.unrealized_pnl} (#{pos.pnl_percentage.round(2)}%)"
  puts "   Position: #{pos.long? ? 'Long' : 'Short'}"
end

# Calculate portfolio metrics
total_value = positions.sum(&:market_value)
total_unrealized_pnl = positions.sum(&:unrealized_pnl)

puts "\nPortfolio Summary:"
puts "Total Market Value: $#{total_value.round(2)}"
puts "Total Unrealized P&L: $#{total_unrealized_pnl.round(2)}"
puts "Number of Positions: #{positions.size}"
```

### Cash Reports

```ruby
# Get cash balances and movements
cash_report = client.flex.cash_report(query_id)

if cash_report
  puts "Cash Report for #{cash_report.account_id}:"
  puts "  Currency: #{cash_report.currency}"
  puts "  Starting Balance: $#{cash_report.starting_cash}"
  puts "  Ending Balance: $#{cash_report.ending_cash}"
  puts "  Net Change: $#{cash_report.net_change}"
  puts "  Deposits: $#{cash_report.deposits}"
  puts "  Withdrawals: $#{cash_report.withdrawals}"
  puts "  Dividends: $#{cash_report.dividends}"
  puts "  Interest: $#{cash_report.interest}"
  puts "  Total Income: $#{cash_report.total_income}"
end
```

### Performance Reports

```ruby
# Get performance metrics
performance = client.flex.performance_report(query_id)

if performance
  puts "Performance Report:"
  puts "  Period: #{performance.period}"
  puts "  Starting NAV: $#{performance.nav_start}"
  puts "  Ending NAV: $#{performance.nav_end}"
  puts "  Total P&L: $#{performance.total_pnl}"
  puts "  Return: #{performance.return_percentage.round(2)}%"
  puts "  Time-Weighted Return: #{performance.twr}"
end
```

## Error Handling Patterns

### Comprehensive Error Handling

```ruby
def safely_fetch_report(flex, query_id)
  begin
    report = flex.generate_and_fetch(query_id, max_wait: 60)
    return { success: true, data: report }
    
  rescue Ibkr::FlexError::ConfigurationError => e
    # Token not configured or invalid
    return {
      success: false,
      error: "Configuration Error",
      message: e.message,
      suggestions: e.suggestions
    }
    
  rescue Ibkr::FlexError::QueryNotFound => e
    # Query ID doesn't exist in Client Portal
    return {
      success: false,
      error: "Query Not Found",
      message: "Query ID #{e.query_id} not found",
      suggestions: [
        "Verify Query ID in Client Portal",
        "Ensure query is active and not deleted",
        "Check that your token has access to this query"
      ]
    }
    
  rescue Ibkr::FlexError::ReportNotReady => e
    # Report still generating after max_wait
    return {
      success: false,
      error: "Timeout",
      message: "Report not ready after #{e.context[:max_wait]} seconds",
      reference_code: e.reference_code,
      retryable: true
    }
    
  rescue Ibkr::FlexError::RateLimitError => e
    # Too many requests
    return {
      success: false,
      error: "Rate Limited",
      message: e.message,
      retry_after: e.retry_after,
      retryable: true
    }
    
  rescue Ibkr::FlexError::NetworkError => e
    # Network connectivity issues
    return {
      success: false,
      error: "Network Error",
      message: e.message,
      retryable: true
    }
    
  rescue Ibkr::FlexError::ParseError => e
    # XML parsing failed
    return {
      success: false,
      error: "Parse Error",
      message: "Failed to parse report XML",
      suggestions: [
        "Report format may have changed",
        "Contact support if issue persists"
      ]
    }
  end
end

# Usage
result = safely_fetch_report(client.flex, "123456")

if result[:success]
  process_report(result[:data])
else
  log_error(result)
  
  if result[:retryable]
    # Schedule retry
    retry_after = result[:retry_after] || 60
    schedule_retry(query_id, retry_after)
  end
end
```

### Retry Logic with Exponential Backoff

```ruby
class FlexReportFetcher
  MAX_RETRIES = 5
  BASE_DELAY = 2  # seconds
  
  def fetch_with_backoff(flex, query_id)
    retries = 0
    
    begin
      flex.generate_and_fetch(query_id)
    rescue Ibkr::FlexError::ReportNotReady, 
           Ibkr::FlexError::NetworkError => e
      if retries < MAX_RETRIES
        retries += 1
        delay = BASE_DELAY ** retries
        puts "Retry #{retries}/#{MAX_RETRIES} after #{delay}s: #{e.message}"
        sleep(delay)
        retry
      else
        raise
      end
    end
  end
end
```

## Production Best Practices

### 1. Token Management

```ruby
# Store tokens securely, never in code
class FlexTokenManager
  def self.get_token
    # Priority order:
    # 1. Environment variable (for containers/cloud)
    return ENV['IBKR_FLEX_TOKEN'] if ENV['IBKR_FLEX_TOKEN']
    
    # 2. Rails credentials (for Rails apps)
    if defined?(Rails) && Rails.application.credentials.ibkr?
      return Rails.application.credentials.ibkr[:flex_token]
    end
    
    # 3. Secrets management service (e.g., AWS Secrets Manager)
    # return fetch_from_secrets_manager('ibkr/flex/token')
    
    raise "Flex token not configured"
  end
end
```

### 2. Caching Reports

```ruby
# Cache frequently accessed reports
class CachedFlexService
  def initialize(flex_client, cache_store = Rails.cache)
    @flex = flex_client
    @cache = cache_store
  end
  
  def get_cached_report(query_id, ttl: 15.minutes)
    cache_key = "flex_report:#{query_id}:#{Date.today}"
    
    @cache.fetch(cache_key, expires_in: ttl) do
      @flex.generate_and_fetch(query_id)
    end
  end
  
  def invalidate_cache(query_id)
    cache_key = "flex_report:#{query_id}:#{Date.today}"
    @cache.delete(cache_key)
  end
end
```

### 3. Background Job Processing

```ruby
# Sidekiq job example
class FetchFlexReportJob
  include Sidekiq::Worker
  sidekiq_options retry: 3, queue: 'reports'
  
  def perform(query_id, user_id)
    user = User.find(user_id)
    flex = Ibkr::Flex.new(token: user.flex_token)
    
    # Generate report
    report = flex.generate_and_fetch(query_id, max_wait: 120)
    
    # Process and store
    process_report(user, report)
    
    # Notify user
    ReportMailer.completed(user, report).deliver_later
    
  rescue Ibkr::FlexError::ReportNotReady => e
    # Retry job later
    self.class.perform_in(5.minutes, query_id, user_id)
    
  rescue => e
    # Log error and notify
    Rails.logger.error "Flex report failed: #{e.message}"
    ReportMailer.failed(user, e.message).deliver_later
    raise  # Let Sidekiq handle retry
  end
  
  private
  
  def process_report(user, report)
    # Store in database
    user.flex_reports.create!(
      query_id: report[:query_id],
      report_type: report[:type],
      data: report,
      generated_at: Time.current
    )
  end
end
```

### 4. Rate Limiting

```ruby
# Implement rate limiting to avoid hitting IBKR limits
class RateLimitedFlexClient
  RATE_LIMIT = 60  # requests per minute
  
  def initialize(flex_client)
    @flex = flex_client
    @limiter = Ratelimit.new("flex_api")
  end
  
  def generate_report(query_id)
    if @limiter.exceeded?("generate", threshold: RATE_LIMIT, interval: 60)
      raise Ibkr::FlexError::RateLimitError.new(
        "Internal rate limit exceeded",
        retry_after: @limiter.ttl("generate")
      )
    end
    
    @limiter.add("generate")
    @flex.generate_report(query_id)
  end
end
```

### 5. Monitoring and Alerting

```ruby
# Track Flex API usage and errors
class MonitoredFlexService
  def initialize(flex_client, metrics_client = StatsD)
    @flex = flex_client
    @metrics = metrics_client
  end
  
  def generate_and_fetch(query_id)
    start_time = Time.now
    
    begin
      report = @flex.generate_and_fetch(query_id)
      
      # Track success
      @metrics.increment('flex.report.success')
      @metrics.timing('flex.report.duration', Time.now - start_time)
      
      report
      
    rescue Ibkr::FlexError => e
      # Track errors by type
      @metrics.increment("flex.report.error.#{e.class.name.demodulize.underscore}")
      
      # Alert on critical errors
      if e.is_a?(Ibkr::FlexError::ConfigurationError)
        AlertService.notify("Flex configuration error: #{e.message}")
      end
      
      raise
    end
  end
end
```

## Troubleshooting

### Common Issues and Solutions

```ruby
# 1. Token Not Working
begin
  flex = Ibkr::Flex.new(token: token)
  flex.generate_report(query_id)
rescue Ibkr::FlexError::ConfigurationError => e
  puts "Token validation failed. Possible issues:"
  puts "- Token may be expired (valid for 1 year)"
  puts "- Token may be for wrong environment (sandbox vs production)"
  puts "- Token format may be incorrect"
  puts "\nGenerate a new token in Client Portal"
end

# 2. Query Not Found
begin
  report = flex.generate_report("999999")
rescue Ibkr::FlexError::QueryNotFound => e
  puts "Query ID not found. Check:"
  puts "- Query ID is correct (copy from Client Portal)"
  puts "- Query is active and not deleted"
  puts "- Your account has access to this query"
  puts "- Token matches the account that owns the query"
end

# 3. Report Takes Too Long
begin
  # Increase timeout for large reports
  report = flex.generate_and_fetch(query_id, 
    max_wait: 300,      # 5 minutes
    poll_interval: 10   # Check every 10 seconds
  )
rescue Ibkr::FlexError::ReportNotReady => e
  puts "Report still generating after timeout."
  puts "For large reports, consider:"
  puts "- Breaking into smaller date ranges"
  puts "- Using fewer report sections"
  puts "- Fetching during off-peak hours"
  puts "- Implementing async processing"
end

# 4. XML Parsing Errors
begin
  report = flex.get_report(reference_code)
rescue Ibkr::FlexError::ParseError => e
  puts "Failed to parse report XML."
  puts "This might indicate:"
  puts "- IBKR changed the report format"
  puts "- Report contains unexpected data"
  puts "- Network issue corrupted the response"
  
  # Try getting raw XML for debugging
  raw_xml = flex.get_report(reference_code, format: :raw)
  File.write("debug_report.xml", raw_xml)
  puts "Raw XML saved to debug_report.xml for analysis"
end
```

### Debug Mode

```ruby
# Enable detailed logging for troubleshooting
Ibkr.configure do |config|
  config.logger_level = :debug
end

# Or create a debug wrapper
class DebugFlexClient
  def initialize(flex_client, logger = Logger.new(STDOUT))
    @flex = flex_client
    @logger = logger
  end
  
  def generate_report(query_id)
    @logger.info "[Flex] Generating report for query: #{query_id}"
    @logger.debug "[Flex] Token present: #{@flex.token.present?}"
    
    start = Time.now
    reference = @flex.generate_report(query_id)
    duration = Time.now - start
    
    @logger.info "[Flex] Report generated in #{duration.round(2)}s"
    @logger.info "[Flex] Reference code: #{reference}"
    
    reference
  rescue => e
    @logger.error "[Flex] Generation failed: #{e.class} - #{e.message}"
    @logger.debug "[Flex] Error context: #{e.respond_to?(:to_h) ? e.to_h : e.inspect}"
    raise
  end
end
```

### Testing with Mock Data

```ruby
# Create a mock Flex client for testing
class MockFlexClient
  def generate_report(query_id)
    "MOCK_REF_#{Time.now.to_i}"
  end
  
  def get_report(reference_code, format: :hash)
    case format
    when :hash
      sample_report_data
    when :model
      Ibkr::Models::FlexReport.new(
        reference_code: reference_code,
        report_type: "AF",
        generated_at: Time.now.to_i * 1000,
        data: sample_report_data
      )
    when :raw
      "<FlexQueryResponse>...</FlexQueryResponse>"
    end
  end
  
  def generate_and_fetch(query_id, **options)
    sample_report_data
  end
  
  private
  
  def sample_report_data
    {
      query_name: "Test Report",
      type: "AF",
      accounts: ["DU123456"],
      transactions: [
        {
          transaction_id: "12345",
          symbol: "AAPL",
          quantity: 100,
          price: 150.0,
          trade_date: Date.today
        }
      ],
      positions: [
        {
          symbol: "AAPL",
          position: 100,
          market_value: 15500.0,
          unrealized_pnl: 500.0
        }
      ]
    }
  end
end

# Use in tests
RSpec.describe "Portfolio Service" do
  let(:flex) { MockFlexClient.new }
  
  it "processes flex reports" do
    report = flex.generate_and_fetch("123456")
    expect(report[:transactions].size).to eq(1)
    expect(report[:positions].first[:symbol]).to eq("AAPL")
  end
end
```

## Summary

The IBKR Flex Web Service provides powerful reporting capabilities with:

- **Two-step process**: Generate then fetch for reliability
- **Multiple formats**: Hash, Model, or Raw XML
- **Comprehensive error handling**: Specific exceptions for each scenario
- **Flexible polling**: Automatic or manual retry logic
- **Type-safe models**: Structured data with convenience methods
- **Production ready**: Thread-safe, with caching and monitoring support

For more information, see the [main README](../README.md) or the [API documentation](./api.md).