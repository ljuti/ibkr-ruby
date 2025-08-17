# frozen_string_literal: true

require_relative "ibkr/version"
require_relative "ibkr/types"
require_relative "ibkr/configuration"
require_relative "ibkr/errors/base"
require_relative "ibkr/errors/authentication_error"
require_relative "ibkr/errors/api_error"
require_relative "ibkr/errors/configuration_error"
require_relative "ibkr/errors/rate_limit_error"
require_relative "ibkr/oauth"
require_relative "ibkr/accounts"
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
  end
end
