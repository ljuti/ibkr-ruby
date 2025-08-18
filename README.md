# IBKR Ruby Gem

[![Gem Version](https://badge.fury.io/rb/ibkr.svg)](https://badge.fury.io/rb/ibkr)
[![Ruby](https://github.com/ljuti/ibkr-ruby/workflows/Ruby/badge.svg)](https://github.com/ljuti/ibkr-ruby/actions)

A modern Ruby gem for accessing Interactive Brokers' Web API. Provides real-time access to portfolio data, account information, and trading functionality with robust error handling and type safety.

## Features

- 🔐 **OAuth 1.0a Authentication** with RSA-SHA256 and HMAC-SHA256 signatures
- 📊 **Portfolio Management** - Real-time account summaries, positions, and transactions
- 📈 **Flex Web Service** - Access pre-configured reports from Client Portal
- 🏦 **Multi-Account Support** - Hybrid approach supporting single and multi-account workflows
- 🛡️ **Type-Safe Data Models** using Dry::Struct and Dry::Types
- ⚡ **Error Handling** with custom error classes for different scenarios
- 🔧 **Flexible Configuration** supporting both sandbox and live trading environments
- 🧵 **Thread-Safe Operations** for concurrent access
- 💾 **Memory Efficient** handling of large datasets

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ibkr'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ibkr
```

## Prerequisites

Before using this gem, you must have:

1. An opened Interactive Brokers account (Demo accounts cannot subscribe to data)
2. An IBKR PRO account type
3. A funded account
4. Developer access with OAuth credentials from IBKR's Self Service Portal

## Quick Start

### Basic Configuration

```ruby
require 'ibkr'

# Configure the gem (typically in an initializer)
Ibkr.configure do |config|
  config.environment = :sandbox  # or :production
  config.timeout = 30
  config.retries = 3
  config.logger_level = :info
end
```

### Authentication and Basic Usage

```ruby
# Create a client for sandbox testing with default account
client = Ibkr::Client.new(default_account_id: "DU123456", live: false)

# Authenticate with IBKR (automatically sets up account access)
client.authenticate

# Check authentication status and active account
puts "Authenticated: #{client.oauth_client.authenticated?}"
puts "Active Account: #{client.account_id}"
puts "Available Accounts: #{client.available_accounts}"
```

### Fluent Interface (New! 🚀)

The IBKR gem now supports a **fluent, chainable API** for more readable and concise code:

```ruby
# Classic approach
client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
client.authenticate
summary = client.accounts.summary
positions = client.accounts.positions(page: 1, sort: "market_value", direction: "desc")

# 🆕 Fluent approach - same functionality, more readable
summary = Ibkr.connect("DU123456", live: false)
  .portfolio
  .summary

positions = Ibkr.connect("DU123456", live: false)
  .portfolio
  .with_page(1)
  .sorted_by("market_value", "desc")
  .positions_with_options
```

#### Fluent Factory Methods

```ruby
# Quick client creation
client = Ibkr.client("DU123456", live: false)

# Account discovery workflow
client = Ibkr.discover_accounts(live: false)

# Connect and authenticate in one call
client = Ibkr.connect("DU123456", live: false)

# Connect and discover all accounts
client = Ibkr.connect_and_discover(live: false)
```

#### Chainable Operations

```ruby
# Switch accounts and chain operations
summary = Ibkr.connect_and_discover(live: false)
  .with_account("DU789012")
  .portfolio
  .summary

# Complex queries with fluent syntax
transactions = Ibkr.connect("DU123456")
  .portfolio
  .for_contract(265598)  # Apple stock
  .for_period(90)        # Last 90 days
  .transactions_with_options

# Paginated positions with sorting
positions = Ibkr.connect("DU123456")
  .portfolio
  .with_page(2)
  .sorted_by("unrealized_pnl", "desc")
  .positions_with_options
```

### Multi-Account Support

The gem supports both single and multi-account workflows through a hybrid approach:

```ruby
# Single Account Workflow (Recommended)
# Specify your default account at initialization
client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
client.authenticate  # Active account is automatically set to DU123456

# Multi-Account Workflow  
# Don't specify default account to discover all available accounts
client = Ibkr::Client.new(live: false)

# When you authenticate without a default account:
# 1. The client calls IBKR's /iserver/accounts API to discover available accounts
# 2. The first account in the response becomes the active account
# 3. You can then switch between any discovered accounts
client.authenticate  

# See all accounts your credentials can access
puts "Available accounts: #{client.available_accounts}"  # e.g., ["DU123456", "DU789012"]
puts "Currently active: #{client.account_id}"            # e.g., "DU123456" (first account)

# Switch between accounts as needed
client.set_active_account("DU789012")
puts "Now using account: #{client.account_id}"  # "DU789012"

# All subsequent API calls use the active account
summary = client.accounts.summary  # Summary for DU789012

# Switch back to another account
client.set_active_account("DU123456")
summary = client.accounts.summary  # Summary for DU123456
```

## Account Discovery & Management

The IBKR gem uses a **hybrid approach** that accommodates both single-account and multi-account workflows. Your IBKR credentials may have access to multiple brokerage accounts, and the gem can automatically discover and manage them.

### How Account Discovery Works

When you authenticate without specifying a `default_account_id`, the client:

1. **Establishes brokerage session** - Calls `/iserver/auth/ssodh/init` with priority access
2. **Discovers available accounts** - Calls `/iserver/accounts` to get all accessible accounts  
3. **Sets active account** - Uses the first account from the response as the active account
4. **Enables account switching** - Allows you to switch between any discovered accounts

```ruby
# Account discovery in action
client = Ibkr::Client.new(live: false)
client.authenticate

# Behind the scenes, this made these API calls:
# 1. POST /iserver/auth/ssodh/init (session initialization)
# 2. GET /iserver/accounts (account discovery)

puts client.available_accounts   # ["DU123456", "DU789012", "DU555555"]
puts client.active_account_id    # "DU123456" (first account)
```

### Account Management Methods

```ruby
# Check what accounts are available
client.available_accounts        # Array of account IDs
client.active_account_id         # Currently active account ID  
client.account_id               # Alias for active_account_id

# Switch active account (must be in available_accounts)
client.set_active_account("DU789012")

# Verify the switch
puts client.account_id          # "DU789012"
```

### When to Use Each Approach

**Single Account (Recommended for most users):**
```ruby
# If you know your account ID and only work with one account
client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
client.authenticate
# ✅ Faster - skips account discovery API call
# ✅ Explicit - you know exactly which account is active
# ✅ Safer - prevents accidental account switching
```

**Multi-Account (For advanced users):**
```ruby
# If you have multiple accounts or don't know your account ID
client = Ibkr::Client.new(live: false)
client.authenticate
# ✅ Automatic discovery - finds all accessible accounts
# ✅ Flexible - can switch between accounts easily
# ✅ Future-proof - handles account additions automatically
```

### Account Information

```ruby
# Get account summary with all balance information
summary = client.accounts.summary
puts "Net Liquidation Value: #{summary.net_liquidation_value.amount}"
puts "Available Funds: #{summary.available_funds.amount}"
puts "Buying Power: #{summary.buying_power.amount}"

# Access individual AccountValue objects
net_liq = summary.net_liquidation_value
puts "Amount: #{net_liq.amount} #{net_liq.currency}"
puts "Timestamp: #{net_liq.timestamp}"
```

### Portfolio Positions

```ruby
# Get current positions with default pagination
positions = client.accounts.positions
positions["results"].each do |position|
  puts "#{position['description']}: #{position['position']} shares"
  puts "Market Value: #{position['market_value']} #{position['currency']}"
  puts "Unrealized P&L: #{position['unrealized_pnl']}"
end

# Get positions with custom sorting and pagination
positions = client.accounts.positions(
  page: 1, 
  sort: "market_value", 
  direction: "desc"
)
```

### Transaction History

```ruby
# Get transaction history for a specific security (last 30 days)
contract_id = 265598  # AAPL contract ID
transactions = client.accounts.transactions(contract_id, days: 30)

transactions.each do |transaction|
  puts "#{transaction['date']}: #{transaction['desc']}"
  puts "Quantity: #{transaction['qty']}, Price: #{transaction['pr']}"
  puts "Amount: #{transaction['amt']} #{transaction['cur']}"
end

# Get last 90 days (default)
transactions = client.accounts.transactions(contract_id)
```

## Flex Web Service

The IBKR Flex Web Service provides access to pre-configured reports that you set up in Client Portal. These reports can include detailed trading activity, positions, cash balances, and performance metrics.

### Prerequisites

1. **Configure Flex Queries in Client Portal**
   - Log into IBKR Client Portal
   - Navigate to Settings → Account Settings → Flex Queries
   - Create a new Flex Query with desired sections (Trades, Positions, Cash, etc.)
   - Note the Query ID for use in the API

2. **Generate Flex Token**
   - In Client Portal, go to Settings → Account Settings → Flex Web Service
   - Generate a new token (valid for 1 year)
   - Store securely - you'll need this for authentication

### Configuration

```ruby
# Option 1: Environment variable
ENV['IBKR_FLEX_TOKEN'] = 'your_flex_token_here'

# Option 2: Configuration
Ibkr.configure do |config|
  config.flex_token = 'your_flex_token_here'
end

# Option 3: Rails credentials (config/credentials.yml.enc)
ibkr:
  flex:
    token: your_flex_token_here
```

### Basic Usage

```ruby
# Initialize client
client = Ibkr::Client.new(default_account_id: "DU123456")

# Access Flex service
flex = client.flex

# Generate and fetch report (two-step process)
query_id = "123456"  # Your Query ID from Client Portal
report = flex.generate_and_fetch(query_id)

# Access report data
puts "Query: #{report[:query_name]}"
puts "Accounts: #{report[:accounts]}"
puts "Transactions: #{report[:transactions].size}"
puts "Positions: #{report[:positions].size}"
```

### Advanced Usage

```ruby
# Step 1: Generate report (returns reference code)
reference_code = flex.generate_report(query_id)
puts "Report reference: #{reference_code}"

# Step 2: Fetch report (can be called multiple times)
report_data = flex.get_report(reference_code)

# Get report as model with convenience methods
report = flex.get_report(reference_code, format: :model)
puts report.trades.size
puts report.positions.first[:symbol]
puts report.cash_reports.first[:ending_cash]

# Get raw XML (for custom parsing)
xml_data = flex.get_report(reference_code, format: :raw)
```

### Service Layer Methods

The Flex service provides high-level methods for specific report types:

```ruby
# Get transactions for a specific period
transactions = client.flex.transactions_report(query_id)
transactions.each do |tx|
  puts "#{tx.symbol}: #{tx.quantity} @ #{tx.price}"
  puts "Net amount: #{tx.net_amount}"
end

# Get current positions
positions = client.flex.positions_report(query_id)
positions.each do |pos|
  puts "#{pos.symbol}: #{pos.position} shares"
  puts "P&L: #{pos.unrealized_pnl}"
end

# Get cash report
cash = client.flex.cash_report(query_id)
puts "Starting cash: #{cash.starting_cash}"
puts "Ending cash: #{cash.ending_cash}"
puts "Net change: #{cash.net_change}"

# Get performance metrics
performance = client.flex.performance_report(query_id)
puts "Total P&L: #{performance.total_pnl}"
puts "Return: #{performance.return_percentage}%"
```

### Data Models

The Flex service returns typed data models for safety and convenience:

```ruby
# FlexReport - Main report container
report = client.flex.get_report(reference_code, format: :model)
report.reference_code    # => "2332907389"
report.report_type       # => "AF" (Activity Flex)
report.generated_at      # => Time object
report.trades           # => Array of transaction hashes
report.positions        # => Array of position hashes

# FlexTransaction - Individual trades
transaction = Ibkr::Models::FlexTransaction.new(tx_data)
transaction.symbol       # => "AAPL"
transaction.quantity     # => 100.0
transaction.price        # => 150.50
transaction.net_amount   # => 15049.0 (proceeds - commission)
transaction.stock?       # => true
transaction.option?      # => false

# FlexPosition - Portfolio positions
position = Ibkr::Models::FlexPosition.new(pos_data)
position.symbol          # => "AAPL"
position.position        # => 100.0
position.market_value    # => 15500.0
position.unrealized_pnl  # => 475.0
position.long?           # => true
position.pnl_percentage  # => 3.16

# FlexCashReport - Cash balances
cash = Ibkr::Models::FlexCashReport.new(cash_data)
cash.currency           # => "USD"
cash.ending_cash        # => 95234.50
cash.net_change         # => -4765.50
cash.total_income       # => 140.0 (dividends + interest)

# FlexPerformance - Performance metrics
perf = Ibkr::Models::FlexPerformance.new(perf_data)
perf.nav_end            # => 115234.50
perf.total_pnl          # => 3765.50
perf.return_percentage  # => 15.23
```

### Error Handling

The Flex service provides specific error classes for different scenarios:

```ruby
begin
  report = client.flex.generate_report(query_id)
rescue Ibkr::FlexError::ConfigurationError => e
  # Token not configured or invalid
  puts "Configuration error: #{e.message}"
  puts "Suggestions: #{e.suggestions.join(', ')}"
rescue Ibkr::FlexError::QueryNotFound => e
  # Query ID doesn't exist
  puts "Query not found: #{e.query_id}"
rescue Ibkr::FlexError::ReportNotReady => e
  # Report still generating (retry after delay)
  if e.retryable?
    sleep(e.retry_after)
    retry
  end
rescue Ibkr::FlexError::RateLimitError => e
  # Too many requests
  puts "Rate limited. Retry after #{e.retry_after} seconds"
rescue Ibkr::FlexError::NetworkError => e
  # Network connectivity issues
  puts "Network error: #{e.message}"
end
```

### Polling for Report Completion

Large reports may take time to generate. The service handles this automatically:

```ruby
# Automatic polling with configurable timeout
report = flex.generate_and_fetch(query_id, 
  max_wait: 60,        # Maximum seconds to wait
  poll_interval: 5     # Seconds between checks
)

# Manual polling
reference_code = flex.generate_report(query_id)
report = nil

10.times do
  begin
    report = flex.get_report(reference_code)
    break if report
  rescue Ibkr::FlexError::ReportNotReady
    sleep(5)
    next
  end
end
```

### Thread Safety

All Flex operations are thread-safe:

```ruby
threads = query_ids.map do |query_id|
  Thread.new do
    client.flex.generate_and_fetch(query_id)
  end
end

reports = threads.map(&:value)
```

## Configuration

### Environment Configuration

```ruby
Ibkr.configure do |config|
  # Environment settings
  config.environment = :sandbox        # :sandbox or :production
  config.base_url = "https://api.ibkr.com"  # Auto-set based on environment
  
  # HTTP settings
  config.timeout = 30                  # Request timeout in seconds
  config.retries = 3                   # Number of retry attempts
  config.user_agent = "IBKR Ruby Client 0.1.0"
  
  # Logging
  config.logger_level = :info          # :debug, :info, :warn, :error
end
```

### OAuth Configuration (Rails Example)

If using Rails, configure OAuth credentials in your credentials file:

```yaml
# config/credentials.yml.enc
ibkr:
  oauth:
    consumer_key: "your_consumer_key"
    access_token: "your_access_token"
    access_token_secret: "base64_encoded_secret"
    base_url: "https://api.ibkr.com"
```

### Cryptographic Files

Place your RSA certificates in the `config/certs/` directory:

```
config/certs/
├── private_encryption.pem    # RSA private key for encryption
├── private_signature.pem     # RSA private key for signatures
└── dhparam.pem              # Diffie-Hellman parameters
```

## Data Models

### AccountSummary

```ruby
summary = client.accounts.summary

# Access structured data
summary.account_id                    # String
summary.net_liquidation_value         # AccountValue object
summary.available_funds               # AccountValue object
summary.buying_power                  # AccountValue object

# AccountValue objects contain:
value = summary.net_liquidation_value
value.amount      # Numeric amount
value.currency    # Currency code (e.g., "USD")
value.timestamp   # Time object
```

### Position Data

```ruby
positions = client.accounts.positions
position = positions["results"].first

# Position attributes
position["conid"]            # Contract ID
position["description"]      # Security description
position["position"]         # Number of shares/contracts
position["market_value"]     # Current market value
position["unrealized_pnl"]   # Unrealized profit/loss
position["average_cost"]     # Average cost basis
```

### Transaction Data

```ruby
transactions = client.accounts.transactions(contract_id)
transaction = transactions.first

# Transaction attributes
transaction["date"]          # Transaction date
transaction["desc"]          # Description
transaction["qty"]           # Quantity
transaction["pr"]            # Price
transaction["amt"]           # Amount
transaction["cur"]           # Currency
```

## Error Handling

The gem provides comprehensive error handling with custom exception classes:

```ruby
begin
  client.authenticate
rescue Ibkr::AuthenticationError => e
  puts "Authentication failed: #{e.message}"
rescue Ibkr::ApiError::RateLimitError => e
  puts "Rate limited. Retry after: #{e.retry_after}"
rescue Ibkr::ApiError::ServerError => e
  puts "IBKR server error: #{e.message}"
rescue Ibkr::ApiError => e
  puts "API error: #{e.message}"
rescue Ibkr::ConfigurationError => e
  puts "Configuration error: #{e.message}"
end
```

### Error Classes

- `Ibkr::AuthenticationError` - Authentication and authorization failures
- `Ibkr::ApiError` - General API errors
  - `Ibkr::ApiError::BadRequest` - 400 errors
  - `Ibkr::ApiError::NotFound` - 404 errors
  - `Ibkr::ApiError::ServerError` - 500+ errors
  - `Ibkr::ApiError::ServiceUnavailable` - 503 errors
- `Ibkr::RateLimitError` - Rate limiting (429 errors)
- `Ibkr::ConfigurationError` - Configuration and setup issues

## Threading and Concurrency

The gem is designed to be thread-safe:

```ruby
# Multiple threads can safely use the same client
threads = []
client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
client.authenticate  # Account is automatically set up

threads << Thread.new { client.accounts.summary }
threads << Thread.new { client.accounts.positions }
threads << Thread.new { client.accounts.transactions(265598) }

results = threads.map(&:join).map(&:value)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies.

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run with coverage
bundle exec rspec --format documentation

# Run specific test files
bundle exec rspec spec/lib/ibkr/client_spec.rb

# Run linting
bundle exec standardrb

# Run tests and linting
rake  # default task
```

### Console

```bash
# Interactive console with gem loaded
bin/console

# In the console:
client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
client.authenticate
# ... experiment with the API
```

### Debugging

Enable debug logging to see detailed HTTP requests:

```ruby
Ibkr.configure do |config|
  config.logger_level = :debug
end
```

## Roadmap

### Completed ✅
- OAuth 1.0a authentication flow
- Multi-account support with hybrid approach
- Account summary, positions, and transactions
- Flex Web Service integration for custom reports
- Type-safe data models with validation
- Comprehensive error handling
- Thread-safe operations
- HTTP client with compression support
- Fluent interface with chainable operations
- Enhanced error context with recovery suggestions
- Refactored test suite (eliminated instance variable anti-patterns)
- XML parsing for Flex reports

### In Progress 🔄
- Full OAuth cryptographic implementation (RSA-SHA256, HMAC-SHA256, Diffie-Hellman)
- WebSocket support for real-time data streaming

### Planned 📋
- Trading operations (place/cancel orders)
- Market data subscriptions
- Real-time portfolio updates
- Advanced position analytics
- Options chain analysis
- Historical data retrieval

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`bundle exec rspec`)
4. Run linting (`bundle exec standardrb`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Testing

The gem includes comprehensive test coverage:

- **403 total tests** (365 passing, 38 pending cryptographic operations)
- Core functionality (Client, Accounts, Models): **100% passing**
- Multi-account workflows: **100% passing**
- Fluent interface: **100% passing**
- Integration tests with proper mocking
- Error handling and edge case coverage
- BDD-style tests focusing on behavior over implementation

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Support

- **Documentation**: See `docs/` directory for detailed API documentation
- **Issues**: Report bugs and feature requests on [GitHub Issues](https://github.com/ljuti/ibkr-ruby/issues)
- **IBKR API Documentation**: [Interactive Brokers Web API](https://www.interactivebrokers.com/campus/ibkr-api-page/cpapi-v1/)

## Disclaimer

This gem is not affiliated with Interactive Brokers LLC. Use at your own risk. Always test thoroughly in sandbox mode before using with live trading accounts.