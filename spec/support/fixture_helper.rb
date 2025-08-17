# frozen_string_literal: true

module FixtureHelper
  def self.fixture_path
    File.expand_path("../fixtures/api_responses", __dir__)
  end

  def self.load_fixture(filename)
    file_path = File.join(fixture_path, filename)
    unless File.exist?(file_path)
      raise ArgumentError, "Fixture file not found: #{filename}"
    end

    JSON.parse(File.read(file_path))
  rescue JSON::ParserError => e
    raise ArgumentError, "Invalid JSON in fixture file #{filename}: #{e.message}"
  end

  # Helper methods for specific fixture categories
  def self.load_accounts_fixture(filename)
    load_fixture("accounts/#{filename}")
  end

  def self.load_portfolio_fixture(filename)
    load_fixture("portfolio/#{filename}")
  end

  def self.load_transactions_fixture(filename)
    load_fixture("transactions/#{filename}")
  end

  def self.load_authentication_fixture(filename)
    load_fixture("authentication/#{filename}")
  end
end

# Include helper methods in RSpec
RSpec.configure do |config|
  config.include FixtureHelper
end