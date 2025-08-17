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

    # Create a client with default account (single-account workflow)
    def client(default_account_id = nil, live: nil)
      Client.new(default_account_id: default_account_id, live: live)
    end

    # Create a client for multi-account discovery workflow
    def discover_accounts(live: nil)
      Client.new(live: live)
    end

    # Create and authenticate client in one call
    def connect(default_account_id = nil, live: nil)
      client(default_account_id, live: live).authenticate!
    end

    # Create, authenticate, and discover accounts
    def connect_and_discover(live: nil)
      discover_accounts(live: live).authenticate!
    end
  end
end
