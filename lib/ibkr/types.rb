# frozen_string_literal: true

require "dry-types"

module Ibkr
  module Types
    include Dry.Types()

    # Custom types for IBKR data
    IbkrNumber = Types::Coercible::Float | Types::Coercible::Integer

    # Position size type that preserves integers when possible
    PositionSize = Types.Constructor(Numeric) do |value|
      case value
      when Integer
        value
      when String
        if value.match?(/\A-?\d+\z/)  # Integer string
          value.to_i
        elsif value.match?(/\A-?\d*\.\d+\z/)  # Float string
          value.to_f
        else
          raise ArgumentError, "Cannot convert string '#{value}' to position size"
        end
      when Numeric
        value.to_s.include?(".") ? value.to_f : value.to_i
      else
        raise ArgumentError, "Cannot convert #{value.class} to position size"
      end
    end

    StringOrNil = Types::String | Types::Nil

    # Time types
    UnixTimestamp = Types::Integer.constructor { |value|
      case value
      when Integer
        value
      when Time
        value.to_i
      when String
        Time.parse(value).to_i
      else
        raise ArgumentError, "Cannot convert #{value.class} to unix timestamp"
      end
    }

    # Coerce unix timestamps to Time objects
    TimeFromUnix = Types.Constructor(Time) do |value|
      case value
      when Time
        value
      when Integer, String
        # IBKR often sends timestamps in milliseconds
        timestamp = value.to_i
        timestamp /= 1000 if timestamp > 4_000_000_000 # Likely milliseconds
        ::Time.at(timestamp)
      else
        raise ArgumentError, "Cannot convert #{value.class} to Time"
      end
    end

    # Environment types
    Environment = Types::String.enum("sandbox", "production")

    # Currency codes
    Currency = Types::String.constrained(format: /\A[A-Z]{3}\z/)
  end
end
