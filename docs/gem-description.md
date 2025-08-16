# IBKR - Ruby Gem for Interactive Brokers Web API

## Description

The **IBKR** gem provides a modern, Ruby-native interface to Interactive Brokers' Web API. This gem enables real-time access to Interactive Brokers' trading functionality, including live market data, portfolio management, and account information. Built with a focus on reliability, type safety, and developer experience.

### Key Features

- **OAuth 1.0a Authentication** with RSA-SHA256 and HMAC-SHA256 signatures
- **Portfolio Management** - Real-time account summaries, positions, and transactions
- **Type-Safe Data Models** using Dry::Struct and Dry::Types
- **Comprehensive Error Handling** with custom error classes for different scenarios
- **Flexible Configuration** supporting both sandbox and live trading environments
- **Thread-Safe Operations** for concurrent access
- **Memory Efficient** handling of large datasets

### Current Implementation Status

**✅ Fully Implemented:**
- OAuth authentication flow with live session tokens
- Client interface with automatic authentication
- Account services (summary, positions, transactions)
- Data models with type validation and coercion
- HTTP client with error handling and compression support
- Configuration management for different environments

**🔄 Partial Implementation:**
- OAuth cryptographic operations (basic structure in place)
- Advanced error recovery and retry logic
- Websocket support (planned for future release)

<usage-requirements>
  To access the Web API, all IBKR accounts must follow a few minimum requirements before data can be received.

  1. Must use an opened IB Account (Demo accounts cannot subscribe to data).
  2. Must use an IBKR PRO account type.
  3. Must maintain a funded account.
</usage-requirements>

## Quick Start

```ruby
require 'ibkr'

# Configure the gem (typically in an initializer)
Ibkr.configure do |config|
  config.environment = :sandbox  # or :production
  config.timeout = 30
  config.retries = 3
end

# Create a client
client = Ibkr::Client.new(live: false)  # sandbox mode

# Authenticate with IBKR
client.authenticate

# Set account ID (required for account operations)
client.set_account_id("DU123456")

# Access account information
summary = client.accounts.summary
puts "Net Liquidation: #{summary.net_liquidation_value.amount}"

# Get positions
positions = client.accounts.positions
positions["results"].each do |position|
  puts "#{position['description']}: #{position['position']} shares"
end

# Get transaction history
transactions = client.accounts.transactions(265598, days: 30)
puts "Found #{transactions.length} transactions"
```

## Architecture Overview

```
Ibkr::Client
├── OAuth Authentication (Ibkr::Oauth)
│   ├── Live Session Tokens
│   ├── Signature Generation (RSA-SHA256, HMAC-SHA256)
│   └── Token Refresh Management
├── HTTP Client (Ibkr::Http::Client)  
│   ├── Request/Response Handling
│   ├── Error Management
│   └── Compression Support
├── Account Services (Ibkr::Accounts)
│   ├── Portfolio Summary
│   ├── Position Management
│   └── Transaction History
└── Data Models
    ├── AccountSummary with AccountValue objects
    ├── Position with P&L calculations
    └── Transaction records
```

## OAuth Implementation

The gem supports **First Party OAuth** for institutions trading on their own behalf:

**First Party Entities:**
- Financial advisors
- Hedge funds  
- Organizations trading their own capital

**Requirements:**
1. Approved IBKR developer account
2. Self Service Portal access for key generation
3. Consumer key, encryption keys, and access tokens
4. Valid RSA certificates for signature generation

**Third Party OAuth** (for platforms serving external users) is planned for future releases.

<documentation>
https://www.interactivebrokers.com/campus/ibkr-api-page/cpapi-v1/#oauth-introduction
</documentation>