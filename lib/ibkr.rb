# frozen_string_literal: true

require_relative "ibkr/version"
require_relative "ibkr/types"
require_relative "ibkr/configuration"
require_relative "ibkr/errors/base"
require_relative "ibkr/errors/authentication_error"
require_relative "ibkr/errors/api_error"
require_relative "ibkr/errors/configuration_error"
require_relative "ibkr/errors/rate_limit_error"
require_relative "ibkr/errors/repository_error"
require_relative "ibkr/oauth"
require_relative "ibkr/accounts"
require_relative "ibkr/chainable_accounts_proxy"
require_relative "ibkr/websocket"
require_relative "ibkr/client"

module Ibkr
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Fluent interface factory methods

    # Creates a new IBKR client instance with optional default account
    #
    # @param default_account_id [String, nil] Account ID to use as default (optional)
    # @param live [Boolean, nil] Environment mode - true for production, false for sandbox
    # @return [Ibkr::Client] A new client instance
    #
    # @example Single account setup
    #   client = Ibkr.client("DU123456", live: false)
    #
    # @example Multi-account discovery
    #   client = Ibkr.client(live: false)
    def client(default_account_id = nil, live: nil)
      Client.new(default_account_id: default_account_id, live: live)
    end

    # Creates a client specifically for multi-account discovery workflow
    #
    # @param live [Boolean, nil] Environment mode - true for production, false for sandbox
    # @return [Ibkr::Client] A new client instance configured for account discovery
    #
    # @example
    #   client = Ibkr.discover_accounts(live: false)
    #   client.authenticate
    #   puts client.available_accounts  # => ["DU123456", "DU789012"]
    def discover_accounts(live: nil)
      Client.new(live: live)
    end

    # Creates and authenticates a client in one call
    #
    # @param default_account_id [String, nil] Account ID to use as default (optional)
    # @param live [Boolean, nil] Environment mode - true for production, false for sandbox
    # @return [Ibkr::Client] An authenticated client instance
    # @raise [Ibkr::AuthenticationError] if authentication fails
    #
    # @example Connect with default account
    #   client = Ibkr.connect("DU123456", live: false)
    #   summary = client.accounts.summary
    def connect(default_account_id = nil, live: nil)
      client(default_account_id, live: live).authenticate!
    end

    # Creates, authenticates, and discovers all available accounts
    #
    # @param live [Boolean, nil] Environment mode - true for production, false for sandbox
    # @return [Ibkr::Client] An authenticated client with discovered accounts
    # @raise [Ibkr::AuthenticationError] if authentication fails
    #
    # @example
    #   client = Ibkr.connect_and_discover(live: false)
    #   puts client.available_accounts  # => ["DU123456", "DU789012"]
    #   client.set_active_account("DU789012")
    def connect_and_discover(live: nil)
      discover_accounts(live: live).authenticate!
    end
  end
end
