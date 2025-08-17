# WebSocket Architecture Design

## Overview

This document outlines the architectural design for adding WebSocket support to the IBKR Ruby gem. The implementation will provide real-time streaming capabilities while maintaining the gem's high-quality standards and integrating seamlessly with existing patterns.

## Table of Contents

- [Architecture Goals](#architecture-goals)
- [Core Components](#core-components)
- [WebSocket Client](#websocket-client)
- [Subscription Management](#subscription-management)
- [Real-time Data Models](#real-time-data-models)
- [Event System](#event-system)
- [Error Handling](#error-handling)
- [Integration Points](#integration-points)
- [Performance Considerations](#performance-considerations)
- [Security & Authentication](#security--authentication)
- [Testing Strategy](#testing-strategy)

## Architecture Goals

### Primary Objectives
1. **Real-time Data Access**: Stream market data, portfolio updates, and order status
2. **Seamless Integration**: Work naturally with existing client and fluent interfaces
3. **Robust Connection Management**: Handle connection failures and automatic reconnection
4. **Performance**: Process high-frequency updates efficiently
5. **Developer Experience**: Intuitive API with comprehensive error context
6. **Reliability**: Bulletproof testing and production-ready resilience

### Design Principles
- **Consistency**: Follow existing gem patterns (Repository, Factory, Enhanced Errors)
- **Backward Compatibility**: Additive changes only, no breaking modifications
- **Thread Safety**: Safe for concurrent access and multi-threaded applications
- **Resource Management**: Proper cleanup and memory efficiency
- **Observability**: Rich logging, metrics, and debugging capabilities

## Core Components

### Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    IBKR Client                          │
├─────────────────────────────────────────────────────────┤
│  HTTP API     │  WebSocket API                          │
│  (Existing)   │  ┌─────────────────────────────────────┐ │
│               │  │        WebSocket Module             │ │
│               │  │  ┌─────────────────────────────────┐ │ │
│               │  │  │     Connection Manager         │ │ │
│               │  │  │  - Authentication              │ │ │
│               │  │  │  - Connection lifecycle        │ │ │
│               │  │  │  - Reconnection strategy       │ │ │
│               │  │  └─────────────────────────────────┘ │ │
│               │  │  ┌─────────────────────────────────┐ │ │
│               │  │  │    Subscription Manager        │ │ │
│               │  │  │  - Market data subscriptions   │ │ │
│               │  │  │  - Portfolio subscriptions     │ │ │
│               │  │  │  - Order status subscriptions  │ │ │
│               │  │  └─────────────────────────────────┘ │ │
│               │  │  ┌─────────────────────────────────┐ │ │
│               │  │  │      Message Router            │ │ │
│               │  │  │  - Message parsing             │ │ │
│               │  │  │  - Event dispatch              │ │ │
│               │  │  │  - Error handling              │ │ │
│               │  │  └─────────────────────────────────┘ │ │
│               │  └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Module Structure

```
lib/ibkr/
├── websocket/
│   ├── client.rb                 # Main WebSocket client
│   ├── connection_manager.rb     # Connection lifecycle management
│   ├── subscription_manager.rb   # Subscription tracking and management
│   ├── message_router.rb         # Message parsing and dispatch
│   ├── reconnection_strategy.rb  # Exponential backoff and retry logic
│   ├── authentication.rb         # WebSocket OAuth authentication
│   ├── models/                   # Real-time data models
│   │   ├── market_data.rb        # Quote, trade, depth data
│   │   ├── portfolio_update.rb   # Portfolio value changes
│   │   └── order_update.rb       # Order status changes
│   ├── streams/                  # Stream-specific logic
│   │   ├── market_data_stream.rb # Market data subscriptions
│   │   ├── portfolio_stream.rb   # Portfolio update subscriptions
│   │   └── order_stream.rb       # Order status subscriptions
│   └── errors/                   # WebSocket-specific errors
│       ├── connection_error.rb   # Connection failures
│       ├── subscription_error.rb # Subscription failures
│       └── authentication_error.rb # WebSocket auth failures
├── websocket.rb                  # Main module and client factory
└── client.rb                    # Add websocket accessor
```

## WebSocket Client

### Core Client Implementation

```ruby
module Ibkr
  module WebSocket
    class Client
      include EventEmitter
      
      attr_reader :connection_manager, :subscription_manager, :message_router
      
      def initialize(ibkr_client)
        @ibkr_client = ibkr_client
        @connection_manager = ConnectionManager.new(self)
        @subscription_manager = SubscriptionManager.new(self)
        @message_router = MessageRouter.new(self)
        @streams = {}
        
        setup_event_handlers
      end
      
      # Connection management
      def connect
        @connection_manager.connect
        self
      end
      
      def disconnect
        @connection_manager.disconnect
        self
      end
      
      def connected?
        @connection_manager.connected?
      end
      
      # Stream accessors (lazy-loaded)
      def market_data
        @streams[:market_data] ||= Streams::MarketDataStream.new(self)
      end
      
      def portfolio
        @streams[:portfolio] ||= Streams::PortfolioStream.new(self)
      end
      
      def orders
        @streams[:orders] ||= Streams::OrderStream.new(self)
      end
      
      # Fluent subscription methods
      def subscribe_to_market_data(symbols)
        market_data.subscribe(symbols)
        self
      end
      
      def subscribe_to_portfolio_updates
        portfolio.subscribe
        self
      end
      
      def subscribe_to_order_status
        orders.subscribe
        self
      end
      
      # Event handling
      def on_message(message)
        @message_router.route(message)
      end
      
      def on_error(error)
        enhanced_error = enhance_websocket_error(error)
        emit(:error, enhanced_error)
      end
      
      private
      
      def setup_event_handlers
        # Connection events
        on(:connected) { emit(:ready) }
        on(:disconnected) { handle_disconnection }
        on(:reconnected) { handle_reconnection }
        
        # Message events
        on(:market_data) { |data| market_data.handle_update(data) }
        on(:portfolio_update) { |data| portfolio.handle_update(data) }
        on(:order_update) { |data| orders.handle_update(data) }
      end
      
      def enhance_websocket_error(error)
        Ibkr::WebSocket::ConnectionError.with_context(
          error.message,
          context: {
            connection_state: @connection_manager.state,
            active_subscriptions: @subscription_manager.active_subscriptions,
            reconnect_attempts: @connection_manager.reconnect_attempts,
            operation: "websocket_operation"
          }
        )
      end
    end
  end
end
```

### Integration with Main Client

```ruby
# In lib/ibkr/client.rb
class Client
  # WebSocket accessor (lazy-loaded)
  def websocket
    @websocket ||= WebSocket::Client.new(self)
  end
  
  # Fluent interface support
  def with_websocket
    websocket.connect
    self
  end
end
```

## Subscription Management

### Subscription Manager

```ruby
module Ibkr
  module WebSocket
    class SubscriptionManager
      attr_reader :subscriptions, :subscription_limits
      
      def initialize(websocket_client)
        @websocket_client = websocket_client
        @subscriptions = {}
        @subscription_limits = {
          market_data: 100,    # Max 100 market data subscriptions
          portfolio: 1,        # Only 1 portfolio subscription
          orders: 1            # Only 1 order subscription
        }
        @rate_limiter = RateLimiter.new
      end
      
      def subscribe(type, identifier = nil, &callback)
        validate_subscription_limit!(type)
        validate_rate_limit!
        
        subscription_key = build_subscription_key(type, identifier)
        
        if @subscriptions[subscription_key]
          raise Ibkr::WebSocket::SubscriptionError.already_subscribed(
            subscription_key,
            context: { active_subscriptions: active_subscriptions.count }
          )
        end
        
        subscription = create_subscription(type, identifier, callback)
        @subscriptions[subscription_key] = subscription
        
        send_subscription_message(subscription)
        subscription
      end
      
      def unsubscribe(type, identifier = nil)
        subscription_key = build_subscription_key(type, identifier)
        subscription = @subscriptions.delete(subscription_key)
        
        if subscription
          send_unsubscription_message(subscription)
          subscription.deactivate
        end
        
        subscription
      end
      
      def active_subscriptions
        @subscriptions.values.select(&:active?)
      end
      
      def handle_subscription_confirmation(message)
        subscription = find_subscription_by_id(message[:subscription_id])
        subscription&.confirm
      end
      
      def handle_subscription_error(message)
        subscription = find_subscription_by_id(message[:subscription_id])
        error = Ibkr::WebSocket::SubscriptionError.subscription_failed(
          message[:error],
          context: {
            subscription_type: subscription&.type,
            subscription_id: message[:subscription_id]
          }
        )
        subscription&.error(error)
      end
      
      private
      
      def validate_subscription_limit!(type)
        current_count = @subscriptions.count { |key, _| key.start_with?(type.to_s) }
        limit = @subscription_limits[type]
        
        if current_count >= limit
          raise Ibkr::WebSocket::SubscriptionError.limit_exceeded(
            type,
            context: { 
              current_count: current_count, 
              limit: limit,
              active_subscriptions: active_subscriptions.map(&:key)
            }
          )
        end
      end
      
      def validate_rate_limit!
        unless @rate_limiter.allow_request?
          raise Ibkr::WebSocket::SubscriptionError.rate_limited(
            context: {
              requests_per_minute: @rate_limiter.requests_per_minute,
              limit: @rate_limiter.limit
            }
          )
        end
      end
    end
  end
end
```

## Real-time Data Models

### Market Data Model

```ruby
module Ibkr
  module WebSocket
    module Models
      class MarketData < Dry::Struct
        include Ibkr::Types
        
        attribute :symbol, String
        attribute :last_price, Decimal.optional
        attribute :bid_price, Decimal.optional
        attribute :ask_price, Decimal.optional
        attribute :bid_size, Integer.optional
        attribute :ask_size, Integer.optional
        attribute :volume, Integer.optional
        attribute :timestamp, Time
        attribute :exchange, String.optional
        attribute :market_status, String.optional
        
        # Calculated fields
        def spread
          return nil unless bid_price && ask_price
          ask_price - bid_price
        end
        
        def mid_price
          return nil unless bid_price && ask_price
          (bid_price + ask_price) / 2
        end
        
        def to_h
          super.merge(
            spread: spread,
            mid_price: mid_price
          )
        end
      end
      
      class MarketDepth < Dry::Struct
        include Ibkr::Types
        
        attribute :symbol, String
        attribute :side, String  # 'bid' or 'ask'
        attribute :levels, Array do
          attribute :price, Decimal
          attribute :size, Integer
          attribute :market_maker, String.optional
        end
        attribute :timestamp, Time
      end
    end
  end
end
```

### Portfolio Update Model

```ruby
module Ibkr
  module WebSocket
    module Models
      class PortfolioUpdate < Dry::Struct
        include Ibkr::Types
        
        attribute :account_id, String
        attribute :net_liquidation_value, Decimal.optional
        attribute :available_funds, Decimal.optional
        attribute :buying_power, Decimal.optional
        attribute :unrealized_pnl, Decimal.optional
        attribute :realized_pnl, Decimal.optional
        attribute :timestamp, Time
        attribute :currency, String.default('USD')
        
        # Position updates (if included)
        attribute :position_updates, Array.optional do
          attribute :symbol, String
          attribute :position, Integer
          attribute :market_value, Decimal
          attribute :unrealized_pnl, Decimal
          attribute :average_cost, Decimal
        end
        
        def total_pnl
          return nil unless unrealized_pnl && realized_pnl
          unrealized_pnl + realized_pnl
        end
      end
    end
  end
end
```

### Order Update Model

```ruby
module Ibkr
  module WebSocket
    module Models
      class OrderUpdate < Dry::Struct
        include Ibkr::Types
        
        attribute :order_id, String
        attribute :account_id, String
        attribute :symbol, String
        attribute :status, String  # submitted, filled, cancelled, rejected, etc.
        attribute :order_type, String  # market, limit, stop, etc.
        attribute :side, String  # buy, sell
        attribute :quantity, Integer
        attribute :filled_quantity, Integer.default(0)
        attribute :remaining_quantity, Integer.optional
        attribute :average_fill_price, Decimal.optional
        attribute :limit_price, Decimal.optional
        attribute :stop_price, Decimal.optional
        attribute :timestamp, Time
        attribute :exchange, String.optional
        
        # Execution details (for fills)
        attribute :executions, Array.optional do
          attribute :execution_id, String
          attribute :price, Decimal
          attribute :quantity, Integer
          attribute :timestamp, Time
          attribute :commission, Decimal.optional
        end
        
        def fully_filled?
          filled_quantity >= quantity
        end
        
        def partially_filled?
          filled_quantity > 0 && filled_quantity < quantity
        end
        
        def total_commission
          executions&.sum { |exec| exec.commission || 0 } || 0
        end
      end
    end
  end
end
```

## Event System

### Event-Driven Architecture

```ruby
module Ibkr
  module WebSocket
    module EventEmitter
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods
        def event_types
          @event_types ||= []
        end
        
        def defines_events(*event_names)
          event_types.concat(event_names)
        end
      end
      
      def initialize_events
        @event_handlers = Hash.new { |h, k| h[k] = [] }
      end
      
      def on(event, &block)
        @event_handlers[event] << block
        self
      end
      
      def off(event, &block)
        @event_handlers[event].delete(block) if block
        self
      end
      
      def emit(event, *args)
        @event_handlers[event].each do |handler|
          begin
            handler.call(*args)
          rescue => e
            handle_event_error(event, e, *args)
          end
        end
      end
      
      private
      
      def handle_event_error(event, error, *args)
        enhanced_error = Ibkr::WebSocket::EventError.handler_failed(
          error.message,
          context: {
            event: event,
            handler_count: @event_handlers[event].size,
            args_count: args.size
          }
        )
        
        emit(:error, enhanced_error)
      end
    end
  end
end
```

### Stream-Specific Events

```ruby
module Ibkr
  module WebSocket
    module Streams
      class MarketDataStream
        include EventEmitter
        
        defines_events :quote_update, :trade_update, :depth_update
        
        def initialize(websocket_client)
          @websocket_client = websocket_client
          @subscriptions = {}
          initialize_events
        end
        
        def subscribe(symbol, &callback)
          subscription = @websocket_client.subscription_manager.subscribe(
            :market_data, 
            symbol,
            &callback
          )
          
          @subscriptions[symbol] = subscription
          
          # Set up event forwarding
          on(:quote_update) do |quote|
            callback.call(quote) if quote.symbol == symbol && callback
          end
          
          subscription
        end
        
        def handle_update(data)
          case data[:type]
          when 'quote'
            quote = Models::MarketData.new(data[:data])
            emit(:quote_update, quote)
          when 'trade'
            trade = Models::TradeData.new(data[:data])
            emit(:trade_update, trade)
          when 'depth'
            depth = Models::MarketDepth.new(data[:data])
            emit(:depth_update, depth)
          end
        end
      end
    end
  end
end
```

## Error Handling

### WebSocket-Specific Errors

```ruby
module Ibkr
  module WebSocket
    class ConnectionError < Ibkr::BaseError
      def self.connection_failed(message, context: {})
        with_context(
          message,
          context: context.merge(
            operation: "websocket_connection",
            category: "connection"
          )
        )
      end
      
      def self.authentication_failed(message, context: {})
        with_context(
          message,
          context: context.merge(
            operation: "websocket_authentication",
            category: "authentication"
          )
        )
      end
      
      def self.reconnection_failed(message, context: {})
        with_context(
          message,
          context: context.merge(
            operation: "websocket_reconnection",
            category: "connection"
          )
        )
      end
    end
    
    class SubscriptionError < Ibkr::BaseError
      def self.limit_exceeded(subscription_type, context: {})
        with_context(
          "Subscription limit exceeded for #{subscription_type}",
          context: context.merge(
            operation: "subscription_management",
            subscription_type: subscription_type
          )
        )
      end
      
      def self.already_subscribed(subscription_key, context: {})
        with_context(
          "Already subscribed to #{subscription_key}",
          context: context.merge(
            operation: "subscription_management",
            subscription_key: subscription_key
          )
        )
      end
      
      def self.rate_limited(context: {})
        with_context(
          "Subscription rate limit exceeded",
          context: context.merge(
            operation: "subscription_rate_limiting"
          )
        )
      end
    end
  end
end
```

### Enhanced Error Context Integration

```ruby
# Enhanced error suggestions for WebSocket issues
def generate_suggestions
  suggestions = super
  
  case self.class.name
  when /WebSocket.*Connection/
    suggestions << "Check network connectivity and firewall settings"
    suggestions << "Verify WebSocket endpoint is accessible"
    suggestions << "Ensure OAuth authentication is valid"
    suggestions << "Try reconnecting with exponential backoff"
  when /WebSocket.*Subscription/
    suggestions << "Check subscription limits for your account type"
    suggestions << "Verify symbol formats and availability"
    suggestions << "Reduce subscription frequency if rate limited"
    suggestions << "Use unsubscribe before resubscribing"
  end
  
  suggestions.uniq
end
```

## Performance Considerations

### Message Processing

```ruby
module Ibkr
  module WebSocket
    class MessageProcessor
      def initialize(websocket_client)
        @websocket_client = websocket_client
        @message_queue = Queue.new
        @processing_thread = nil
        @metrics = PerformanceMetrics.new
      end
      
      def start_processing
        @processing_thread = Thread.new do
          while message = @message_queue.pop
            process_message_with_metrics(message)
          end
        end
      end
      
      def enqueue_message(message)
        @message_queue.push(message)
      end
      
      private
      
      def process_message_with_metrics(message)
        start_time = Time.now
        
        begin
          @websocket_client.message_router.route(message)
          @metrics.record_success(Time.now - start_time)
        rescue => e
          @metrics.record_error(Time.now - start_time, e)
          handle_processing_error(e, message)
        end
      end
      
      def handle_processing_error(error, message)
        enhanced_error = Ibkr::WebSocket::MessageProcessingError.with_context(
          "Failed to process WebSocket message: #{error.message}",
          context: {
            message_type: message[:type],
            processing_time: Time.now - start_time,
            queue_size: @message_queue.size,
            operation: "message_processing"
          }
        )
        
        @websocket_client.emit(:error, enhanced_error)
      end
    end
  end
end
```

### Memory Management

```ruby
module Ibkr
  module WebSocket
    class SubscriptionCache
      MAX_CACHE_SIZE = 10_000
      CLEANUP_THRESHOLD = 0.8
      
      def initialize
        @cache = {}
        @access_times = {}
        @cache_hits = 0
        @cache_misses = 0
      end
      
      def get(key)
        if @cache.key?(key)
          @access_times[key] = Time.now
          @cache_hits += 1
          @cache[key]
        else
          @cache_misses += 1
          nil
        end
      end
      
      def set(key, value)
        cleanup_if_needed
        
        @cache[key] = value
        @access_times[key] = Time.now
      end
      
      def cleanup_if_needed
        return unless @cache.size > MAX_CACHE_SIZE * CLEANUP_THRESHOLD
        
        # Remove oldest 20% of entries
        entries_to_remove = (@cache.size * 0.2).to_i
        oldest_keys = @access_times.sort_by { |_, time| time }.first(entries_to_remove).map(&:first)
        
        oldest_keys.each do |key|
          @cache.delete(key)
          @access_times.delete(key)
        end
      end
      
      def stats
        {
          cache_size: @cache.size,
          hit_rate: @cache_hits.to_f / (@cache_hits + @cache_misses),
          memory_usage: @cache.size * 100  # Rough estimate
        }
      end
    end
  end
end
```

## Security & Authentication

### WebSocket Authentication

```ruby
module Ibkr
  module WebSocket
    class Authentication
      def initialize(ibkr_client)
        @ibkr_client = ibkr_client
      end
      
      def authenticate_websocket
        unless @ibkr_client.authenticated?
          raise Ibkr::WebSocket::AuthenticationError.not_authenticated(
            context: { operation: "websocket_authentication_check" }
          )
        end
        
        # Generate WebSocket-specific authentication token
        ws_token = generate_websocket_token
        
        {
          token: ws_token,
          account_id: @ibkr_client.account_id,
          timestamp: Time.now.to_i
        }
      end
      
      private
      
      def generate_websocket_token
        # Use existing OAuth client to generate WebSocket token
        auth_data = {
          oauth_token: @ibkr_client.oauth_client.access_token,
          timestamp: Time.now.to_i,
          nonce: SecureRandom.hex(16)
        }
        
        signature = @ibkr_client.oauth_client.sign_request(
          "GET",
          websocket_endpoint,
          auth_data
        )
        
        auth_data.merge(oauth_signature: signature)
      end
      
      def websocket_endpoint
        case @ibkr_client.environment
        when "production"
          "wss://api.ibkr.com/v1/api/ws"
        else
          "wss://api.ibkr.com/v1/api/ws"  # IBKR uses same endpoint
        end
      end
    end
  end
end
```

## Integration Points

### Repository Pattern Integration

```ruby
# WebSocket data can feed into repositories for caching
module Ibkr
  module Repositories
    class StreamingAccountRepository < BaseRepository
      def initialize(client)
        super(client)
        @websocket_client = client.websocket
        @cache = {}
        
        setup_websocket_listeners
      end
      
      def find_summary(account_id)
        # Try cache first, fall back to API
        @cache[account_id] || super
      end
      
      private
      
      def setup_websocket_listeners
        @websocket_client.portfolio.on(:update) do |portfolio_update|
          # Cache real-time portfolio data
          @cache[portfolio_update.account_id] = transform_to_summary(portfolio_update)
        end
      end
      
      def transform_to_summary(portfolio_update)
        # Transform WebSocket portfolio update to AccountSummary format
        Ibkr::Models::AccountSummary.new(
          account_id: portfolio_update.account_id,
          net_liquidation_value: portfolio_update.net_liquidation_value,
          # ... other transformations
        )
      end
    end
  end
end
```

### Fluent Interface Integration

```ruby
# WebSocket methods integrate with fluent interfaces
module Ibkr
  class Client
    def stream_market_data(*symbols)
      websocket.connect.subscribe_to_market_data(symbols)
      self
    end
    
    def stream_portfolio
      websocket.connect.subscribe_to_portfolio_updates
      self
    end
    
    def stream_orders
      websocket.connect.subscribe_to_order_status
      self
    end
  end
end

# Usage:
client = Ibkr.connect("DU123456")
  .stream_market_data("AAPL", "MSFT") 
  .stream_portfolio
  .stream_orders
```

## Testing Strategy

The comprehensive BDD testing strategy created by the dan-north agent covers:

### Test Categories
1. **Feature Tests**: High-level streaming scenarios
2. **Unit Tests**: Component-level WebSocket functionality  
3. **Integration Tests**: End-to-end WebSocket workflows
4. **Performance Tests**: High-frequency message processing
5. **Security Tests**: Authentication and data protection

### Key Test Scenarios
- Connection lifecycle management
- Real-time data streaming accuracy
- Subscription management and limits
- Reconnection and error recovery
- Performance under load
- Security and authentication
- Memory efficiency and cleanup

### Mock Strategy
- WebSocket connection mocking with Faye::WebSocket
- EventMachine timer simulation
- Message flow simulation
- Network failure simulation

This architecture provides a robust foundation for WebSocket support that integrates seamlessly with the existing IBKR gem while maintaining high standards for performance, reliability, and developer experience.