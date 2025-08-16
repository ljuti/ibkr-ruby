# IBKR Ruby Gem - Complete Documentation

## Overview

The IBKR Ruby gem provides a comprehensive interface to Interactive Brokers' Web API, enabling Ruby applications to access real-time trading functionality, market data, portfolio updates, and market scanners.

## Features

- **OAuth Authentication**: First-party OAuth implementation for IBKR accounts
- **HTTP API Client**: Synchronous access to IBKR trading endpoints
- **WebSocket Support**: Asynchronous, event-driven real-time data streaming
- **Market Data**: Live market data access and market scanners
- **Portfolio Management**: Real-time portfolio updates and position tracking
- **Trading Operations**: Order placement, modification, and cancellation

## Requirements

### Account Prerequisites
- **Active IBKR Account**: Demo accounts cannot subscribe to data
- **IBKR PRO Account**: Standard accounts are not supported
- **Funded Account**: Account must maintain funding
- **First-Party Entity**: Initially supports first-party OAuth only

### Technical Requirements
- Ruby >= 3.2.0
- OAuth consumer key and encryption keys from IBKR Self Service Portal

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ibkr'
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install ibkr
```

## Configuration

### OAuth Setup

```ruby
Ibkr.configure do |config|
  config.consumer_key = ENV['IBKR_CONSUMER_KEY']
  config.private_key_path = ENV['IBKR_PRIVATE_KEY_PATH']
  config.oauth_callback_url = ENV['IBKR_OAUTH_CALLBACK_URL']
  config.environment = :production # or :sandbox
end
```

### Environment Variables

```bash
IBKR_CONSUMER_KEY=your_consumer_key
IBKR_PRIVATE_KEY_PATH=/path/to/private_key.pem
IBKR_OAUTH_CALLBACK_URL=https://your-app.com/oauth/callback
```

## Usage

### Authentication

```ruby
# Initialize OAuth flow
auth_url = Ibkr::OAuth.authorization_url(state: 'your_state')
# Redirect user to auth_url

# Handle callback
access_token = Ibkr::OAuth.get_access_token(
  authorization_code: params[:code],
  state: params[:state]
)

# Create authenticated client
client = Ibkr::Client.new(access_token: access_token)
```

### Market Data

```ruby
# Get market data for a symbol
market_data = client.market_data.snapshot(symbol: 'AAPL')

# Subscribe to real-time data
client.websocket.subscribe_market_data('AAPL') do |data|
  puts "Price update: #{data[:last_price]}"
end
```

### Portfolio Operations

```ruby
# Get account summary
account = client.portfolio.account_summary

# Get positions
positions = client.portfolio.positions

# Get portfolio performance
performance = client.portfolio.performance
```

### Trading

```ruby
# Place a market order
order = client.trading.place_order(
  symbol: 'AAPL',
  side: 'BUY',
  quantity: 100,
  order_type: 'MKT'
)

# Get order status
status = client.trading.order_status(order.id)

# Cancel order
client.trading.cancel_order(order.id)
```

### Market Scanners

```ruby
# Run market scanner
results = client.scanners.run(
  scanner_type: 'TOP_PERC_GAIN',
  instrument: 'STK',
  location: 'STK.US.MAJOR'
)
```

## API Reference

### Client Classes

- `Ibkr::Client` - Main API client
- `Ibkr::OAuth` - OAuth authentication handler
- `Ibkr::WebSocket` - WebSocket connection manager

### Service Modules

- `Ibkr::MarketData` - Market data operations
- `Ibkr::Portfolio` - Portfolio and account operations
- `Ibkr::Trading` - Order management and trading
- `Ibkr::Scanners` - Market scanner operations

### Error Handling

```ruby
begin
  client.trading.place_order(invalid_params)
rescue Ibkr::AuthenticationError => e
  # Handle authentication issues
rescue Ibkr::RateLimitError => e
  # Handle rate limiting
rescue Ibkr::APIError => e
  # Handle general API errors
end
```

## WebSocket Events

```ruby
client.websocket.on_connect do
  puts "Connected to IBKR WebSocket"
end

client.websocket.on_disconnect do
  puts "Disconnected from IBKR WebSocket"
end

client.websocket.on_error do |error|
  puts "WebSocket error: #{error.message}"
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt.

### Running Tests

```bash
# Run all tests
rake spec

# Run specific test file
bundle exec rspec spec/ibkr/client_spec.rb

# Run with coverage
COVERAGE=true rake spec
```

### Code Quality

```bash
# Run linter
bundle exec standardrb

# Auto-fix linting issues
bundle exec standardrb --fix
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ljuti/ibkr.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Support

- [IBKR Web API Documentation](https://www.interactivebrokers.com/campus/ibkr-api-page/cpapi-v1/)
- [OAuth Setup Guide](docs/oauth-setup.md)
- [API Reference](docs/api-reference.md)