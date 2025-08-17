# frozen_string_literal: true

require_relative "websocket/errors"
require_relative "websocket/event_emitter"
require_relative "websocket/authentication"
require_relative "websocket/connection_manager"
require_relative "websocket/subscription_manager"
require_relative "websocket/message_router"
require_relative "websocket/reconnection_strategy"
require_relative "websocket/client"

module Ibkr
  # WebSocket module providing real-time streaming capabilities for the IBKR gem
  #
  # Features:
  # - Real-time market data streaming
  # - Portfolio and account value streaming  
  # - Order status and execution streaming
  # - Automatic connection management and reconnection
  # - Subscription management with rate limiting
  # - Event-driven architecture with callbacks
  # - Automatic EventMachine management for console/REPL usage
  #
  # @example Basic usage
  #   client = Ibkr::Client.new(default_account_id: "DU123456", live: false)
  #   websocket = client.websocket
  #   
  #   websocket.connect  # Automatically starts EventMachine if needed
  #   websocket.subscribe_market_data(["AAPL"], ["price", "volume"])
  #   websocket.on_market_data { |data| puts "#{data[:symbol]}: $#{data[:price]}" }
  #
  # @example Fluent interface
  #   client.websocket
  #     .connect
  #     .subscribe_market_data(["AAPL", "MSFT"], ["price"])
  #     .subscribe_portfolio("DU123456")
  #     .subscribe_orders("DU123456")
  #
  # @example Console/REPL usage
  #   # EventMachine is automatically started in a background thread
  #   websocket = client.websocket
  #   websocket.connect  # Works in IRB/console without blocking
  #   
  #   # Check EventMachine status
  #   websocket.eventmachine_status  # => { running: true, thread_running: true }
  #   
  #   # Clean shutdown (optional, useful when exiting console)
  #   websocket.stop_eventmachine!
  #
  module WebSocket
  end
end