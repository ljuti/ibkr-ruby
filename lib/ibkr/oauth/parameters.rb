# frozen_string_literal: true

module Ibkr
  module Oauth
    # Base class for OAuth parameters
    # Manages OAuth parameter construction and validation
    class Parameters
      attr_reader :config, :signature_generator

      def initialize(config:, signature_generator:)
        @config = config
        @signature_generator = signature_generator
        @params = {}
      end

      def reset
        @params = {}
        self
      end

      def add_consumer_key
        @params["oauth_consumer_key"] = config.consumer_key
        self
      end

      def add_access_token
        @params["oauth_token"] = config.access_token
        self
      end

      def add_nonce
        @params["oauth_nonce"] = signature_generator.generate_nonce
        self
      end

      def add_timestamp
        @params["oauth_timestamp"] = signature_generator.generate_timestamp
        self
      end

      def add_realm
        @params["realm"] = config.production? ? "limited_poa" : "test_realm"
        self
      end

      def build
        @params.dup
      end

      protected

      def add_signature_method(method)
        @params["oauth_signature_method"] = method
        self
      end

      def add_signature(signature)
        @params["oauth_signature"] = URI.encode_www_form_component(signature)
        self
      end
    end

    # Authentication-specific OAuth parameters
    class AuthenticationParameters < Parameters
      def add_diffie_hellman_challenge
        @params["diffie_hellman_challenge"] = signature_generator.generate_dh_challenge
        self
      end

      def add_rsa_signature
        signature = signature_generator.generate_rsa_signature(@params)
        add_signature(signature)
        self
      end

      def build_complete
        reset
          .add_consumer_key
          .add_access_token
          .add_nonce
          .add_timestamp
          .add_signature_method("RSA-SHA256")
          .add_diffie_hellman_challenge
          .add_rsa_signature
          .add_realm
          .build
      end
    end

    # API request OAuth parameters
    class ApiParameters < Parameters
      attr_reader :request_params

      def initialize(config:, signature_generator:, request_params: {})
        super(config: config, signature_generator: signature_generator)
        @request_params = request_params
      end

      def add_hmac_signature
        signature = signature_generator.generate_hmac_signature(
          method: request_params[:method],
          url: request_params[:url],
          params: @params,
          query: request_params[:query] || {},
          body: request_params[:body] || {},
          live_session_token: request_params[:live_session_token]
        )
        add_signature(signature)
        self
      end

      def build_complete
        reset
          .add_consumer_key
          .add_access_token
          .add_nonce
          .add_timestamp
          .add_signature_method("HMAC-SHA256")
          .add_hmac_signature
          .add_realm
          .build
      end
    end
  end
end
