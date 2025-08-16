# IBKR Gem API Documentation

## Table of Contents

- [Configuration](#configuration)
- [Client](#client)
- [OAuth Authentication](#oauth-authentication)
- [Account Services](#account-services)
- [Data Models](#data-models)
- [Error Handling](#error-handling)
- [Types System](#types-system)

## Configuration

### Ibkr.configure

Configure the gem globally. Typically done in an initializer.

```ruby
Ibkr.configure do |config|
  config.environment = :sandbox        # :sandbox or :production
  config.base_url = nil                # Auto-set based on environment
  config.timeout = 30                  # HTTP timeout in seconds
  config.retries = 3                   # Number of retry attempts
  config.user_agent = "IBKR Ruby Client 0.1.0"
  config.logger_level = :info          # :debug, :info, :warn, :error
end
```

**Parameters:**
- `environment` (Symbol): `:sandbox` or `:production`
- `base_url` (String, optional): API base URL (auto-detected from environment)
- `timeout` (Integer): HTTP request timeout in seconds
- `retries` (Integer): Number of retry attempts for failed requests
- `user_agent` (String): User agent string for HTTP requests
- `logger_level` (Symbol): Logging level

**Returns:** `Ibkr::Configuration`

### Ibkr.configuration

Access the current configuration.

```ruby
config = Ibkr.configuration
puts config.environment  # => :sandbox
```

**Returns:** `Ibkr::Configuration`

## Client

### Ibkr::Client.new

Creates a new IBKR client instance.

```ruby
client = Ibkr::Client.new(live: false, config: nil)
```

**Parameters:**
- `live` (Boolean, optional): `true` for production, `false` for sandbox. Defaults to configuration setting.
- `config` (Ibkr::Configuration, optional): Custom configuration. Defaults to global configuration.

**Returns:** `Ibkr::Client`

### #authenticate

Authenticate with Interactive Brokers using OAuth 1.0a.

```ruby
client.authenticate
```

**Returns:** `Boolean` - `true` if authentication successful

**Raises:**
- `Ibkr::AuthenticationError` - Invalid credentials or authentication failure
- `Ibkr::ApiError` - Network or API errors

### #set_account_id

Set the account ID for subsequent account operations.

```ruby
client.set_account_id("DU123456")
```

**Parameters:**
- `account_id` (String): IBKR account identifier

**Returns:** `String` - The set account ID

### #account_id

Get the currently set account ID.

```ruby
account_id = client.account_id  # => "DU123456"
```

**Returns:** `String` or `nil`

### #accounts

Access account services for portfolio and transaction data.

```ruby
accounts = client.accounts  # => Ibkr::Accounts
```

**Returns:** `Ibkr::Accounts` (memoized)

### #oauth_client

Access the OAuth client for authentication operations.

```ruby
oauth = client.oauth_client  # => Ibkr::Oauth::Client
```

**Returns:** `Ibkr::Oauth::Client` (memoized)

## OAuth Authentication

### Ibkr::Oauth.new

Create a new OAuth client (rarely needed directly).

```ruby
oauth = Ibkr::Oauth.new(live: false, config: nil)
```

**Parameters:**
- `live` (Boolean, optional): Production mode flag
- `config` (Ibkr::Configuration, optional): Custom configuration

**Returns:** `Ibkr::Oauth::Client`

### OAuth Client Methods

#### #authenticate

Perform OAuth authentication flow.

```ruby
oauth_client.authenticate
```

**Returns:** `Boolean`

#### #authenticated?

Check if currently authenticated.

```ruby
oauth_client.authenticated?  # => true/false
```

**Returns:** `Boolean`

#### #token

Get the current live session token.

```ruby
token = oauth_client.token  # => Ibkr::Oauth::LiveSessionToken or nil
```

**Returns:** `Ibkr::Oauth::LiveSessionToken` or `nil`

#### #logout

Logout and invalidate the current session.

```ruby
oauth_client.logout
```

**Returns:** `Boolean`

## Account Services

### Ibkr::Accounts

Account services are accessed through the client:

```ruby
accounts = client.accounts
```

### #summary

Get comprehensive account summary with all balance information.

```ruby
summary = accounts.summary
```

**Returns:** `Ibkr::Models::AccountSummary`

**Raises:**
- `Ibkr::AuthenticationError` - Client not authenticated
- `Ibkr::ApiError` - API request failed

**Example:**
```ruby
summary = client.accounts.summary
puts "Net Liquidation: #{summary.net_liquidation_value.amount}"
puts "Available Funds: #{summary.available_funds.amount}"
puts "Buying Power: #{summary.buying_power.amount}"
```

### #positions

Get current portfolio positions with optional pagination and sorting.

```ruby
positions = accounts.positions(page: 0, sort: "description", direction: "asc")
```

**Parameters:**
- `page` (Integer, optional): Page number for pagination (default: 0)
- `sort` (String, optional): Sort field (default: "description")
- `direction` (String, optional): Sort direction "asc" or "desc" (default: "asc")

**Returns:** `Hash` with "results" array containing position data

**Example:**
```ruby
positions = client.accounts.positions(sort: "market_value", direction: "desc")
positions["results"].each do |position|
  puts "#{position['description']}: #{position['position']} shares"
  puts "Market Value: #{position['market_value']}"
end
```

### #transactions

Get transaction history for a specific contract.

```ruby
transactions = accounts.transactions(contract_id, days = 90, currency: "USD")
```

**Parameters:**
- `contract_id` (Integer): IBKR contract identifier
- `days` (Integer, optional): Number of days of history (default: 90)
- `currency` (String, optional): Currency filter (default: "USD")

**Returns:** `Array` of transaction hashes

**Example:**
```ruby
# Get last 30 days of AAPL transactions
transactions = client.accounts.transactions(265598, days: 30)
transactions.each do |transaction|
  puts "#{transaction['date']}: #{transaction['desc']}"
  puts "Amount: #{transaction['amt']} #{transaction['cur']}"
end
```

### #get

Get raw account metadata (low-level method).

```ruby
metadata = accounts.get
```

**Returns:** `Hash` with account metadata

## Data Models

All data models are built with Dry::Struct for type safety and validation.

### Ibkr::Models::AccountSummary

Comprehensive account summary with typed balance information.

#### Attributes

- `account_id` (String): Account identifier
- `net_liquidation_value` (AccountValue): Total account value
- `available_funds` (AccountValue): Available for withdrawal
- `buying_power` (AccountValue): Available for purchases
- `accrued_cash` (AccountValue, optional): Accrued interest
- `equity_with_loan` (AccountValue, optional): Equity including margin
- `excess_liquidity` (AccountValue, optional): Excess liquidity
- `gross_position_value` (AccountValue, optional): Total position value
- `initial_margin` (AccountValue, optional): Initial margin requirement
- `maintenance_margin` (AccountValue, optional): Maintenance margin
- `total_cash_value` (AccountValue, optional): Total cash

#### Example Usage

```ruby
summary = client.accounts.summary

# Access individual values
net_liq = summary.net_liquidation_value
puts "Amount: #{net_liq.amount}"      # Numeric value
puts "Currency: #{net_liq.currency}"  # Currency code
puts "Timestamp: #{net_liq.timestamp}" # Time object

# Direct access to amounts
puts "Net Liquidation: #{summary.net_liquidation_value.amount}"
puts "Buying Power: #{summary.buying_power.amount}"
```

### Ibkr::Models::AccountValue

Represents a monetary value with currency and timestamp.

#### Attributes

- `amount` (Numeric): Monetary amount
- `currency` (String): Currency code (e.g., "USD")
- `timestamp` (Time): When the value was recorded

#### Example

```ruby
value = summary.net_liquidation_value
puts "#{value.amount} #{value.currency} as of #{value.timestamp}"
```

### Ibkr::Models::Position

Portfolio position data with calculations and validation.

#### Key Attributes

- `conid` (String): Contract identifier
- `position` (Integer/Float): Number of shares/contracts (preserves type)
- `description` (String): Security description
- `currency` (String): Position currency
- `market_value` (Numeric): Current market value
- `market_price` (Numeric): Current market price
- `average_cost` (Numeric, optional): Average cost basis
- `unrealized_pnl` (Numeric): Unrealized profit/loss
- `realized_pnl` (Numeric): Realized profit/loss
- `security_type` (String): Security type (STK, OPT, etc.)
- `asset_class` (String): Asset class (STOCK, OPTION, etc.)
- `sector` (String): Market sector
- `group` (String): Sub-sector group

#### Helper Methods

```ruby
position = Ibkr::Models::Position.new(position_data)

# Position direction
position.long?    # => true if position > 0
position.short?   # => true if position < 0  
position.flat?    # => true if position == 0

# P&L calculations
position.total_pnl           # Combined realized + unrealized
position.pnl_percentage      # P&L as percentage of cost basis
position.notional_value      # Market price × position size
position.cost_basis         # Average cost × position size

# Risk metrics
position.exposure_percentage(account_net_liq)  # Position size vs account

# Display helpers
position.formatted_position  # "100" (integer) or "100.5" (float)
position.position_summary    # "LONG 100 APPLE INC"
position.attention_needed?   # True if large unrealized loss

# Summary for reporting
position.summary_hash        # Hash with key metrics
```

### Ibkr::Models::Transaction

Transaction record data.

#### Attributes

- `date` (String): Transaction date
- `description` (String): Transaction description
- `quantity` (Numeric): Number of shares/contracts
- `price` (Numeric): Execution price
- `amount` (Numeric): Total transaction amount
- `currency` (String): Transaction currency
- `contract_id` (String): Related contract identifier
- `type` (String): Transaction type

## Error Handling

The gem provides a comprehensive error hierarchy for different failure scenarios.

### Error Hierarchy

```
Ibkr::Error (StandardError)
├── Ibkr::BaseError
│   ├── Ibkr::AuthenticationError
│   ├── Ibkr::ConfigurationError
│   ├── Ibkr::RateLimitError
│   └── Ibkr::ApiError
│       ├── Ibkr::ApiError::BadRequest (400)
│       ├── Ibkr::ApiError::NotFound (404)
│       ├── Ibkr::ApiError::ServerError (500+)
│       ├── Ibkr::ApiError::ServiceUnavailable (503)
│       └── Ibkr::ApiError::ValidationError
```

### Error Classes

#### Ibkr::AuthenticationError

Authentication and authorization failures.

```ruby
begin
  client.authenticate
rescue Ibkr::AuthenticationError => e
  puts "Auth failed: #{e.message}"
  puts "Details: #{e.details}"
end
```

**Common causes:**
- Invalid OAuth credentials
- Expired tokens
- Insufficient permissions

#### Ibkr::ApiError

General API request failures.

```ruby
begin
  client.accounts.summary
rescue Ibkr::ApiError => e
  puts "API Error: #{e.message}"
  puts "Status: #{e.code}"
  puts "Response: #{e.response}"
end
```

**Attributes:**
- `code` (Integer): HTTP status code
- `details` (Hash): Additional error context
- `response` (Object): Original HTTP response

#### Ibkr::RateLimitError

Rate limiting (429 errors).

```ruby
begin
  client.accounts.positions
rescue Ibkr::RateLimitError => e
  puts "Rate limited. Retry after: #{e.retry_after} seconds"
  sleep(e.retry_after)
  retry
end
```

**Attributes:**
- `retry_after` (Integer): Seconds to wait before retry

#### Ibkr::ConfigurationError

Configuration and setup issues.

```ruby
begin
  Ibkr::Client.new
rescue Ibkr::ConfigurationError => e
  puts "Config error: #{e.message}"
end
```

### Error Context

All errors include contextual information:

```ruby
begin
  client.accounts.summary
rescue Ibkr::BaseError => e
  puts "Error: #{e.message}"
  puts "Context: #{e.to_h}"
  puts "Timestamp: #{e.timestamp}"
  puts "Request ID: #{e.request_id}" if e.request_id
end
```

## Types System

The gem uses Dry::Types for type safety and automatic coercion.

### Built-in Types

#### Ibkr::Types::IbkrNumber

Coerces to Float or Integer based on input.

```ruby
# "100" => 100 (Integer)
# "100.5" => 100.5 (Float)
# 100 => 100 (Integer)
```

#### Ibkr::Types::PositionSize

Preserves integer values when possible, used for position quantities.

```ruby
# "100" => 100 (Integer)
# "100.5" => 100.5 (Float)
# Raises error for non-numeric strings
```

#### Ibkr::Types::TimeFromUnix

Converts IBKR millisecond timestamps to Ruby Time objects.

```ruby
# 1692000000000 => Time object (converts from milliseconds)
# 1692000000 => Time object (seconds)
# Time object => Time object (passthrough)
```

#### Ibkr::Types::Currency

Validates 3-letter currency codes.

```ruby
# "USD" => "USD"
# "EUR" => "EUR"
# "us" => raises validation error
```

#### Ibkr::Types::Environment

Validates environment settings.

```ruby
# "sandbox" => "sandbox"
# "production" => "production"
# "test" => raises validation error
```

### Custom Type Usage

When creating new models, use appropriate types:

```ruby
class MyModel < Ibkr::Models::Base
  attribute :amount, Ibkr::Types::IbkrNumber
  attribute :currency, Ibkr::Types::Currency
  attribute :timestamp, Ibkr::Types::TimeFromUnix
  attribute? :optional_field, Ibkr::Types::String.optional
end
```

**Type Modifiers:**
- `.optional` - Allows nil values
- `.default(value)` - Provides default value
- `.constrained(rule)` - Adds validation constraints

## Threading and Concurrency

The gem is designed to be thread-safe for all operations:

```ruby
client = Ibkr::Client.new(live: false)
client.authenticate
client.set_account_id("DU123456")

# Safe to use across multiple threads
threads = [
  Thread.new { client.accounts.summary },
  Thread.new { client.accounts.positions },
  Thread.new { client.accounts.transactions(265598) }
]

results = threads.map(&:join).map(&:value)
```

**Thread Safety Features:**
- Memoized services are thread-safe
- HTTP client connection pooling
- Atomic operations for authentication state
- Immutable data models

## Advanced Usage

### Custom Configuration

```ruby
# Custom configuration per client
config = Ibkr::Configuration.new
config.timeout = 60
config.environment = :production

client = Ibkr::Client.new(config: config)
```

### Debug Logging

```ruby
# Enable detailed request/response logging
Ibkr.configure do |config|
  config.logger_level = :debug
end

# All HTTP requests and responses will be logged
```

### Error Recovery

```ruby
def robust_account_summary(client)
  retries = 3
  begin
    client.accounts.summary
  rescue Ibkr::RateLimitError => e
    sleep(e.retry_after)
    retry
  rescue Ibkr::ApiError::ServerError => e
    retries -= 1
    if retries > 0
      sleep(2)
      retry
    else
      raise
    end
  end
end
```

This documentation covers the complete public API of the IBKR gem. For implementation details and development guidance, see the CLAUDE.md file.