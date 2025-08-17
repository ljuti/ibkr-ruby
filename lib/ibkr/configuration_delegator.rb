# frozen_string_literal: true

module Ibkr
  # Module for delegating configuration-related methods.
  #
  # This module provides a clean way to access configuration properties
  # without cluttering the main client class with simple delegation methods.
  # It eliminates repetitive configuration accessor methods.
  #
  # @example
  #   class MyClient
  #     include Ibkr::ConfigurationDelegator
  #
  #     private
  #
  #     def config_object
  #       @config
  #     end
  #   end
  #
  module ConfigurationDelegator
    # Get the current environment.
    #
    # @return [String] The current environment ("sandbox" or "production")
    def environment
      config_object.environment
    end

    # Check if client is in sandbox mode.
    #
    # @return [Boolean] true if in sandbox mode
    def sandbox?
      config_object.sandbox?
    end

    # Check if client is in production mode.
    #
    # @return [Boolean] true if in production mode
    def production?
      config_object.production?
    end

    private

    # Abstract method that must be implemented by including classes.
    #
    # @return [Ibkr::Configuration] The configuration object
    # @raise [NotImplementedError] if not implemented by including class
    def config_object
      raise NotImplementedError, "Including class must implement #config_object method"
    end
  end
end