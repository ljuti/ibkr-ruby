# IBKR Ruby Gem Usage Guide

## Quick Start: Accessing Transaction History

This guide shows how to use the IBKR gem to connect to an Interactive Brokers account and browse transaction history.

### Installation

```ruby
# Gemfile
gem 'ibkr'
```

### Basic Setup and Authentication

```ruby
require 'ibkr'

# Create a client (sandbox mode for testing)
client = Ibkr::Client.new(
  default_account_id: "DU123456",  # Your IBKR account ID
  live: false                       # Use true for production
)

# Authenticate with IBKR
client.authenticate!
# => Returns the client for chaining

# Check if authenticated
client.authenticated?
# => true
```

### Accessing Transaction History

```ruby
# Get account service
accounts = client.accounts

# Get transaction history for a specific contract
# Parameters: contract_id, days_back, currency (optional)
transactions = accounts.transactions("265598", 90, currency: "USD")

# Each transaction includes:
# - trade_date: When the trade occurred
# - symbol: Security symbol
# - description: Transaction description  
# - quantity: Number of shares/contracts
# - price: Execution price
# - amount: Total transaction amount
# - commission: Trading commission
# - currency: Transaction currency
# - asset_class: Type of security (STK, OPT, etc.)

transactions.each do |transaction|
  puts "#{transaction.trade_date}: #{transaction.symbol} - #{transaction.quantity} @ #{transaction.price}"
end
```

### Complete Example: Browse Transaction History

```ruby
require 'ibkr'

# Setup and authenticate
client = Ibkr::Client.new(
  default_account_id: "DU123456",
  live: false
)

begin
  # Authenticate
  client.authenticate!
  puts "✓ Connected to IBKR"
  
  # Get available accounts
  puts "Available accounts: #{client.available_accounts.join(', ')}"
  
  # Access account services
  accounts = client.accounts
  
  # Get account summary
  summary = accounts.summary
  puts "Net Liquidation Value: #{summary.net_liquidation_value.amount} #{summary.net_liquidation_value.currency}"
  
  # Get all positions
  positions = accounts.positions
  puts "\nCurrent Positions:"
  positions.each do |position|
    puts "- #{position.symbol}: #{position.position} shares @ #{position.market_price}"
  end
  
  # Get transaction history for specific contracts
  # First, you might want to get contract IDs from positions
  if positions.any?
    contract_id = positions.first.contract_id
    
    # Get 90 days of transaction history
    transactions = accounts.transactions(contract_id, 90)
    
    puts "\nRecent Transactions:"
    transactions.each do |txn|
      puts "#{txn.trade_date}: #{txn.description}"
      puts "  Quantity: #{txn.quantity}"
      puts "  Price: #{txn.price} #{txn.currency}"
      puts "  Commission: #{txn.commission}"
    end
  end
  
rescue Ibkr::AuthenticationError => e
  puts "Authentication failed: #{e.message}"
rescue Ibkr::ApiError => e
  puts "API error: #{e.message}"
end
```

### Fluent Interface for Chaining

The gem supports method chaining for more concise code:

```ruby
client
  .authenticate!
  .with_account("DU123456")
  .portfolio
  .summary
  # => Returns account summary for DU123456

# Stream real-time data (WebSocket)
client
  .with_websocket
  .stream_market_data("AAPL", "MSFT")
  .stream_portfolio
  .stream_orders
```

### Working with Multiple Accounts

```ruby
# Authenticate and discover accounts
client.authenticate!

# List all available accounts
client.available_accounts
# => ["DU123456", "DU789012"]

# Switch active account
client.set_active_account("DU789012")

# Or use fluent interface
client.with_account("DU789012").accounts.summary
```

### Error Handling

The gem provides specific error types for different scenarios:

```ruby
begin
  client.authenticate!
  transactions = client.accounts.transactions("265598", 30)
rescue Ibkr::AuthenticationError => e
  # Handle authentication issues
  puts "Auth failed: #{e.message}"
  puts "Context: #{e.context}"
rescue Ibkr::RateLimitError => e
  # Handle rate limiting
  puts "Rate limited. Retry after: #{e.retry_after}"
rescue Ibkr::ApiError::NotFound => e
  # Handle missing resources
  puts "Resource not found: #{e.message}"
rescue Ibkr::ApiError => e
  # Handle other API errors
  puts "API error: #{e.message}"
end
```

### Configuration

```ruby
# Global configuration
Ibkr.configure do |config|
  config.timeout = 30        # Request timeout in seconds
  config.retries = 3         # Number of retries
  config.logger_level = :info
end

# Per-client configuration
config = Ibkr::Configuration.new
config.timeout = 60

client = Ibkr::Client.new(
  config: config,
  default_account_id: "DU123456",
  live: false
)
```

### Pagination for Large Result Sets

```ruby
# Get positions with pagination
page = 0
all_positions = []

loop do
  positions = accounts.positions(page: page, sort: "symbol", direction: "asc")
  break if positions.empty?
  
  all_positions.concat(positions)
  page += 1
end

# Or use the convenience method
all_positions = accounts.all_positions
```

### WebSocket Streaming (Real-time Data)

```ruby
# Setup WebSocket connection
websocket = client.websocket

# Connect and authenticate
websocket.connect
websocket.authenticate

# Subscribe to market data
websocket.subscribe_to_market_data(["AAPL", "MSFT"], ["price", "volume"])

# Handle incoming messages
websocket.on(:market_data) do |data|
  puts "#{data[:symbol]}: #{data[:price]}"
end

# Subscribe to portfolio updates
websocket.subscribe_to_portfolio_updates(client.account_id)

websocket.on(:portfolio_update) do |update|
  puts "Portfolio update: #{update.inspect}"
end

# Start receiving messages
websocket.start
```

## Key Classes and Methods

### Ibkr::Client
- `authenticate!` - Authenticate with IBKR
- `authenticated?` - Check authentication status
- `accounts` - Access account services
- `websocket` - Access WebSocket client
- `available_accounts` - List available accounts
- `set_active_account(id)` - Switch active account

### Ibkr::Accounts  
- `summary` - Get account summary with balances
- `positions(page: 0)` - Get positions (paginated)
- `transactions(contract_id, days)` - Get transaction history
- `all_positions` - Get all positions (handles pagination)

### Ibkr::Models::Transaction
- `trade_date` - Transaction date
- `symbol` - Security symbol
- `quantity` - Number of shares/contracts
- `price` - Execution price
- `commission` - Trading commission
- `amount` - Total amount
- `currency` - Transaction currency

### Ibkr::Models::Position
- `symbol` - Security symbol
- `position` - Number of shares
- `market_price` - Current market price
- `market_value` - Total market value
- `unrealized_pnl` - Unrealized P&L
- `realized_pnl` - Realized P&L

## Environment Variables

For Rails applications, store credentials in encrypted credentials:

```yaml
# config/credentials.yml.enc
ibkr:
  oauth:
    consumer_key: "your_key"
    access_token: "your_token"
    access_token_secret: "your_secret"
```

For non-Rails applications, use environment variables:

```bash
export IBKR_OAUTH_CONSUMER_KEY="your_key"
export IBKR_OAUTH_ACCESS_TOKEN="your_token"
export IBKR_OAUTH_ACCESS_TOKEN_SECRET="your_secret"
```

## Testing

Use sandbox mode for testing:

```ruby
# Sandbox client (no real trades)
client = Ibkr::Client.new(
  default_account_id: "DU123456",
  live: false  # Sandbox mode
)

# Production client (real trades)
client = Ibkr::Client.new(
  default_account_id: "U123456",
  live: true   # Production mode
)

# Check current mode
client.sandbox?    # => true/false
client.production? # => true/false
```

## Troubleshooting

### Authentication Issues
- Ensure OAuth credentials are properly configured
- Check if using correct environment (sandbox vs production)
- Verify account ID is correct

### Rate Limiting
- The gem automatically handles rate limiting with retries
- Monitor `Ibkr::RateLimitError` for manual handling

### Connection Issues
- Check network connectivity
- Verify IBKR API gateway is accessible
- For WebSocket, ensure firewall allows WSS connections

## Additional Resources

- [IBKR API Documentation](https://www.interactivebrokers.com/api)
- [OAuth Setup Guide](./docs/oauth_setup.md)
- [WebSocket Guide](./docs/websocket.md)
- [Error Handling Guide](./docs/error_handling.md)