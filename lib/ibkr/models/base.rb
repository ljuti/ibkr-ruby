# frozen_string_literal: true

require "dry-struct"

module Ibkr
  module Models
    class Base < Dry::Struct
      # Transform keys from strings to symbols
      transform_keys(&:to_sym)

      # Make attributes accessible
      def to_h
        super.compact
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      # Allow checking if attribute is present
      def has_attribute?(name)
        respond_to?(name)
      end

      # Get attribute value with default
      def attribute_value(name, default = nil)
        return default unless has_attribute?(name)

        value = send(name)
        value.nil? ? default : value
      end

      # Pretty inspect output
      def inspect
        attrs = to_h.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
        "#<#{self.class.name} #{attrs}>"
      end
    end
  end
end
