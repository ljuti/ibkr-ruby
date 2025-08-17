# frozen_string_literal: true

require "openssl"
require "base64"
require "securerandom"
require "uri"
require "cgi"

module Ibkr
  module Oauth
    class SignatureGenerator
      # Test-specific accessor for @dh_random - allows tests to verify DH implementation
      attr_accessor :dh_random

      def initialize(config)
        @config = config
      end

      # Generate RSA-SHA256 signature for live session token request
      def generate_rsa_signature(params)
        params_for_signature = params.reject { |k, _| k == "oauth_signature" || k == "realm" }
        base_string = encoded_base_string(params_for_signature)

        raw_signature = @config.signature_key.sign(OpenSSL::Digest.new("SHA256"), base_string)
        Base64.strict_encode64(raw_signature)
      end

      # Generate HMAC-SHA256 signature for API requests
      def generate_hmac_signature(method:, url:, params:, live_session_token:, query: {}, body: {})
        base_string = canonical_base_string(method, url, params, query, body)
        raw_key = Base64.decode64(live_session_token)
        raw_signature = OpenSSL::HMAC.digest("sha256", raw_key, base_string.encode("utf-8"))

        signature = Base64.strict_encode64(raw_signature)
        URI.encode_www_form_component(signature)
      end

      # Generate secure nonce
      def generate_nonce(length = 16)
        chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
        length.times.map { chars.sample }.join
      end

      # Generate current timestamp
      def generate_timestamp
        Time.now.to_i.to_s
      end

      # Generate Diffie-Hellman challenge
      def generate_dh_challenge
        @dh_random = SecureRandom.random_number(2**256)

        dh_prime = @config.dh_params.p
        dh_generator = @config.dh_params.g

        dh_generator.mod_exp(@dh_random, dh_prime).to_s(16)
      end

      # Compute live session token from DH response
      def compute_live_session_token(dh_response)
        raise ArgumentError, "DH challenge must be generated first" unless @dh_random

        b_bn = OpenSSL::BN.new(dh_response, 16)
        a_bn = OpenSSL::BN.new(@dh_random.to_s(16), 16)
        p_bn = @config.dh_params.p

        k_bn = b_bn.mod_exp(a_bn, p_bn)
        hex_k = k_bn.to_s(16)
        hex_k = "0" + hex_k if hex_k.length.odd?

        k_bytes = [hex_k].pack("H*")
        k_bytes = "\x00" + k_bytes if (k_bn.num_bits % 8).zero?

        prepend_bytes = [decrypt_prepend].pack("H*")
        hmac = OpenSSL::HMAC.digest("sha1", k_bytes, prepend_bytes)

        Base64.strict_encode64(hmac)
      end

      private

      # Create base string for RSA signature (live session token request)
      def encoded_base_string(params)
        flat_params = flatten_params(params)
        params_string = flat_params.sort.map { |k, v| "#{k}=#{v}" }.join("&")

        method = "POST"
        url = "#{@config.base_url}/v1/api/oauth/live_session_token"
        prepend = decrypt_prepend

        base_string = "#{prepend}#{method}&#{URI.encode_www_form_component(url)}&#{URI.encode_www_form_component(params_string)}"
        base_string.encode("utf-8")
      end

      # Create canonical base string for HMAC signature (API requests)
      def canonical_base_string(method, url, headers, query = {}, form = {})
        # Collect all parameters that must be signed
        param_hash = headers.dup
        param_hash.merge!(query) if query && !query.empty?
        param_hash.merge!(form) if form && !form.empty?

        # Flatten complex values
        flat_params = flatten_params(param_hash)
        param_string = flat_params.sort.map { |k, v| "#{k}=#{v}" }.join("&")

        # Percent-encode URL and parameter string per RFC 3986
        encoded_url = CGI.escape(url)
        encoded_param = CGI.escape(param_string)

        "#{method.upcase}&#{encoded_url}&#{encoded_param}"
      end

      # Flatten nested parameters (arrays and hashes) for OAuth signature
      def flatten_params(params, prefix = nil)
        params.flat_map do |k, v|
          key = prefix ? "#{prefix}[#{k}]" : k.to_s
          case v
          when Array
            v.flat_map { |item| flatten_params({key => item}) }
          when Hash
            flatten_params(v, key)
          else
            [[key, v]]
          end
        end
      end

      # Decrypt the prepend value from access token secret
      def decrypt_prepend
        encrypted_secret = Base64.decode64(@config.access_token_secret)
        decrypted_bytes = @config.encryption_key.private_decrypt(
          encrypted_secret,
          OpenSSL::PKey::RSA::PKCS1_PADDING
        )

        decrypted_bytes.unpack1("H*")
      rescue OpenSSL::PKey::RSAError => e
        raise Ibkr::ConfigurationError, "Failed to decrypt access token secret: #{e.message}"
      end
    end
  end
end
