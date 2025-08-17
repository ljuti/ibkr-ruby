# frozen_string_literal: true

require "anyway_config"
require "openssl"

module Ibkr
  class Configuration < Anyway::Config
    config_name :ibkr

    # Environment and connection settings
    attr_config :environment, :base_url, :timeout, :retries

    # OAuth credentials
    attr_config :consumer_key, :access_token, :access_token_secret

    # Cryptographic key file paths
    attr_config :private_key_path, :signature_key_path, :dh_param_path

    # Direct key content (for testing or containers)
    attr_config :private_key_content, :signature_key_content, :dh_param_content

    # Optional settings
    attr_config :logger_level, :user_agent

    # Defaults
    def initialize(*)
      super

      self.environment ||= "sandbox"
      self.timeout ||= 30
      self.retries ||= 3
      self.logger_level ||= "info"
      self.user_agent ||= "IBKR Ruby Client #{Ibkr::VERSION}"
    end

    # Environment helpers
    def sandbox?
      environment == "sandbox"
    end

    def production?
      environment == "production"
    end

    # Dynamic base URL based on environment
    def base_url
      super || default_base_url
    end

    # Validation
    def validate!
      errors = []

      errors << "consumer_key is required" if consumer_key.nil? || consumer_key.empty?
      errors << "access_token is required" if access_token.nil? || access_token.empty?
      errors << "access_token_secret is required" if access_token_secret.nil? || access_token_secret.empty?
      errors << "environment must be 'sandbox' or 'production'" unless %w[sandbox production].include?(environment)

      unless crypto_keys_available?
        errors << "cryptographic keys must be provided (either as file paths or content)"
      end

      unless errors.empty?
        raise Ibkr::ConfigurationError, "Configuration invalid: #{errors.join(", ")}"
      end

      true
    end

    # Cryptographic key accessors with lazy loading
    def encryption_key
      @encryption_key ||= load_key(:private_key)
    end

    def signature_key
      @signature_key ||= load_key(:signature_key)
    end

    def dh_params
      @dh_params ||= load_dh_params
    end

    # Reset cached keys (useful for testing)
    def reset_keys!
      @encryption_key = nil
      @signature_key = nil
      @dh_params = nil
    end

    private

    def default_base_url
      case environment
      when "production"
        "https://api.ibkr.com"
      when "sandbox"
        "https://api.ibkr.com" # IBKR uses same URL with different auth realm
      else
        raise Ibkr::ConfigurationError, "Unknown environment: #{environment}"
      end
    end

    def crypto_keys_available?
      has_key?(:private_key) && has_key?(:signature_key) && has_key?(:dh_param)
    end

    def has_key?(key_type)
      path_attr = "#{key_type}_path"
      content_attr = "#{key_type}_content"

      (send(path_attr) && File.exist?(send(path_attr))) ||
        !send(content_attr).nil?
    end

    def load_key(key_type)
      content = load_key_content(key_type)
      OpenSSL::PKey::RSA.new(content)
    rescue OpenSSL::PKey::RSAError => e
      raise Ibkr::ConfigurationError, "Invalid #{key_type}: #{e.message}"
    end

    def load_dh_params
      content = load_key_content(:dh_param)
      OpenSSL::PKey::DH.new(content)
    rescue OpenSSL::PKey::DHError => e
      raise Ibkr::ConfigurationError, "Invalid DH parameters: #{e.message}"
    end

    def load_key_content(key_type)
      path_attr = "#{key_type}_path"
      content_attr = "#{key_type}_content"

      # Try content first, then file path
      content = send(content_attr)
      return content unless content.nil?

      path = send(path_attr)
      if path && File.exist?(path)
        File.read(path)
      else
        raise Ibkr::ConfigurationError, "#{key_type.to_s.tr("_", " ")} not found: #{path || "no path provided"}"
      end
    end
  end
end
