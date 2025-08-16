# frozen_string_literal: true

require_relative "lib/ibkr/version"

Gem::Specification.new do |spec|
  spec.name = "ibkr"
  spec.version = Ibkr::VERSION
  spec.authors = ["Lauri Jutila"]
  spec.email = ["git@laurijutila.com"]

  spec.summary = "Ruby client for Interactive Brokers Web API"
  spec.description = "A comprehensive Ruby gem for accessing Interactive Brokers' Web API, providing real-time market data, trading functionality, portfolio management, and WebSocket support for event-driven applications."
  spec.homepage = "https://github.com/ljuti/ibkr"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ljuti/ibkr"
  spec.metadata["changelog_uri"] = "https://github.com/ljuti/ibkr/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "dry-struct", "~> 1.6"
  spec.add_dependency "dry-types", "~> 1.7"
  spec.add_dependency "anyway_config", "~> 2.6"
  spec.add_dependency "websocket-driver", "~> 0.7"
  spec.add_dependency "concurrent-ruby", "~> 1.2"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
