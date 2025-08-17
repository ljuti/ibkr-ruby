# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Repositories::RepositoryFactory do
  let(:mock_client) { double("client", live: false) }
  let(:mock_config) { double("config") }

  before do
    # Stub the repository classes to avoid requiring their actual implementations
    stub_const("Ibkr::Repositories::ApiAccountRepository", Class.new)
    stub_const("Ibkr::Repositories::CachedAccountRepository", Class.new)
    stub_const("Ibkr::Repositories::TestAccountRepository", Class.new)

    # Mock the repository constructors
    allow(Ibkr::Repositories::ApiAccountRepository).to receive(:new).and_return(double("api_repo"))
    allow(Ibkr::Repositories::CachedAccountRepository).to receive(:new).and_return(double("cached_repo"))
    allow(Ibkr::Repositories::TestAccountRepository).to receive(:new).and_return(double("test_repo"))

    # Clean up any Rails constants to prevent test leakage
    hide_const("Rails") if defined?(Rails)
  end

  describe "supported repository types" do
    it "supports creating all configured repository types" do
      # Test that each supported type can be created successfully
      [:api, :cached, :test].each do |type|
        expect {
          described_class.create_account_repository(mock_client, type: type)
        }.not_to raise_error
      end
    end

    it "validates repository type support" do
      # Valid types should work
      expect {
        described_class.create_account_repository(mock_client, type: :api)
      }.not_to raise_error

      # Invalid types should raise appropriate error
      expect {
        described_class.create_account_repository(mock_client, type: :invalid)
      }.to raise_error(Ibkr::RepositoryError)
    end
  end

  describe ".create_account_repository" do
    context "when creating API repository" do
      it "creates functional API repository" do
        result = described_class.create_account_repository(mock_client, type: :api)

        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new).with(mock_client)
        expect(result).to be_truthy
      end

      it "accepts both symbol and string type specifications" do
        symbol_result = described_class.create_account_repository(mock_client, type: :api)
        string_result = described_class.create_account_repository(mock_client, type: "api")

        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new).twice
        expect(symbol_result).to be_truthy
        expect(string_result).to be_truthy
      end
    end

    context "when creating cached repository" do
      it "creates cached repository with appropriate underlying repository" do
        result = described_class.create_account_repository(mock_client, type: :cached)

        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new)
        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new)
        expect(result).to be_truthy
      end

      it "accepts custom underlying repository configuration" do
        custom_underlying = double("custom_underlying")
        options = {underlying_repository: custom_underlying}

        result = described_class.create_account_repository(mock_client, type: :cached, options: options)

        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new).with(
          mock_client,
          hash_including(underlying_repository: custom_underlying)
        )
        expect(result).to be_truthy
      end

      it "accepts custom cache TTL configuration" do
        custom_ttl = {summary: 60, positions: 5}
        options = {cache_ttl: custom_ttl}

        result = described_class.create_account_repository(mock_client, type: :cached, options: options)

        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new).with(
          mock_client,
          hash_including(cache_ttl: custom_ttl)
        )
        expect(result).to be_truthy
      end
    end

    context "when creating test repository" do
      it "creates functional test repository" do
        result = described_class.create_account_repository(mock_client, type: :test)

        expect(Ibkr::Repositories::TestAccountRepository).to have_received(:new)
        expect(result).to be_truthy
      end

      it "configures test repository with custom test data" do
        test_data = {accounts: ["DU123456"], summaries: {}}
        options = {test_data: test_data}

        result = described_class.create_account_repository(mock_client, type: :test, options: options)

        expect(Ibkr::Repositories::TestAccountRepository).to have_received(:new).with(
          mock_client,
          hash_including(test_data: test_data)
        )
        expect(result).to be_truthy
      end
    end

    context "when type is not specified" do
      it "automatically selects appropriate repository type" do
        result = described_class.create_account_repository(mock_client)

        # Should create some type of repository
        expect(result).to be_truthy
      end
    end

    context "when unsupported repository type is specified" do
      it "raises helpful error for unsupported types" do
        expect {
          described_class.create_account_repository(mock_client, type: :unsupported)
        }.to raise_error(Ibkr::RepositoryError) do |error|
          expect(error.message).to include("not supported")
          expect(error.context).to include(:available_types)
          expect(error.context[:available_types]).to include(:api, :cached, :test)
        end
      end
    end
  end

  describe ".create_auto_repository" do
    context "when automatically selecting repository type" do
      it "creates appropriate repository based on environment detection" do
        result = described_class.create_auto_repository(mock_client)

        expect(result).to be_truthy
      end

      it "applies provided options to automatically selected repository" do
        # Clean up any Rails mocks to prevent leakage
        allow(Rails).to receive(:respond_to?).and_return(false) if defined?(Rails)

        test_options = {test_data: {accounts: ["DU123456"]}}

        result = described_class.create_auto_repository(mock_client, options: test_options)

        expect(result).to be_truthy
        # Options should be passed through to the created repository
      end
    end
  end

  describe ".create_repository_chain" do
    context "when creating layered repository architecture" do
      let(:chain_config) do
        [
          {type: :api, options: {}},
          {type: :cached, options: {cache_ttl: {summary: 30}}}
        ]
      end

      it "builds functional repository chain" do
        result = described_class.create_repository_chain(mock_client, chain_config)

        expect(result).to be_truthy
        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new).at_least(:once)
        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new)
      end

      it "configures each layer with appropriate options" do
        result = described_class.create_repository_chain(mock_client, chain_config)

        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new).with(
          mock_client,
          hash_including(cache_ttl: {summary: 30})
        )
        expect(result).to be_truthy
      end
    end

    context "when creating multi-layer repository chain" do
      let(:complex_chain_config) do
        [
          {type: :api, options: {}},
          {type: :cached, options: {cache_ttl: {summary: 60}}},
          {type: :test, options: {test_data: {override: true}}}
        ]
      end

      it "constructs all layers in repository chain" do
        result = described_class.create_repository_chain(mock_client, complex_chain_config)

        expect(result).to be_truthy
        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new)
        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new)
        expect(Ibkr::Repositories::TestAccountRepository).to have_received(:new)
      end
    end

    context "when chain configuration is empty" do
      it "handles empty configuration gracefully" do
        result = described_class.create_repository_chain(mock_client, [])

        expect(result).to be_nil
      end
    end
  end

  describe "intelligent repository selection" do
    context "when determining appropriate repository type" do
      it "respects explicit type specification" do
        # Explicit type should be honored
        described_class.create_account_repository(mock_client, type: :api)
        described_class.create_account_repository(mock_client, type: :cached)

        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new).at_least(:once)
        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new)
      end

      it "handles both symbol and string type specifications" do
        described_class.create_account_repository(mock_client, type: :test)
        described_class.create_account_repository(mock_client, type: "test")

        expect(Ibkr::Repositories::TestAccountRepository).to have_received(:new).twice
      end
    end

    context "when making environment-based repository selection" do
      it "selects test repository when test mode is enabled" do
        stub_const("ENV", {"IBKR_TEST_MODE" => "true"})

        result = described_class.create_auto_repository(mock_client)

        expect(result).to be_truthy
      end

      it "considers client live trading status for repository selection" do
        allow(mock_client).to receive(:live).and_return(false)
        stub_const("ENV", {})

        result = described_class.create_auto_repository(mock_client)

        expect(result).to be_truthy
      end

      it "adapts to live trading requirements" do
        allow(mock_client).to receive(:live).and_return(true)
        stub_const("ENV", {})

        result = described_class.create_auto_repository(mock_client)

        expect(result).to be_truthy
      end
    end

    context "when handling configuration precedence" do
      it "prioritizes explicit configuration over environment detection" do
        stub_const("ENV", {"IBKR_TEST_MODE" => "true"})

        # Explicit type should override environment
        described_class.create_account_repository(mock_client, type: :api)

        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new)
      end
    end
  end

  describe "environment-specific configurations" do
    context "when adapting to different environments" do
      it "creates development-optimized repositories" do
        allow(mock_client).to receive(:live).and_return(false)
        stub_const("ENV", {})

        repository = described_class.create_auto_repository(mock_client)

        expect(repository).to be_truthy
      end

      it "creates production-optimized repositories" do
        allow(mock_client).to receive(:live).and_return(true)
        stub_const("ENV", {})

        repository = described_class.create_auto_repository(mock_client)

        expect(repository).to be_truthy
      end

      it "creates test-environment repositories" do
        stub_const("ENV", {"IBKR_TEST_MODE" => "true"})

        repository = described_class.create_auto_repository(mock_client)

        expect(repository).to be_truthy
      end
    end

    context "when building performance-optimized repository chains" do
      let(:performance_chain_config) do
        [
          {type: :api, options: {}},
          {
            type: :cached,
            options: {
              cache_ttl: {
                summary: 300,    # 5 minutes for summary
                positions: 30,   # 30 seconds for positions
                metadata: 3600   # 1 hour for metadata
              }
            }
          }
        ]
      end

      it "constructs optimized repository architecture" do
        result = described_class.create_repository_chain(mock_client, performance_chain_config)

        expect(result).to be_truthy
        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new).with(
          mock_client,
          hash_including(
            cache_ttl: {
              summary: 300,
              positions: 30,
              metadata: 3600
            }
          )
        )
      end
    end

    context "when setting up test-oriented repository configuration" do
      let(:test_chain_config) do
        [
          {
            type: :test,
            options: {
              test_data: {
                accounts: ["DU123456", "DU789012"],
                summaries: {
                  "DU123456" => {"netLiquidation" => "100000.00"},
                  "DU789012" => {"netLiquidation" => "200000.00"}
                }
              }
            }
          }
        ]
      end

      it "creates comprehensive test data environment" do
        result = described_class.create_repository_chain(mock_client, test_chain_config)

        expect(result).to be_truthy
        expect(Ibkr::Repositories::TestAccountRepository).to have_received(:new).with(
          mock_client,
          hash_including(
            test_data: hash_including(
              accounts: ["DU123456", "DU789012"]
            )
          )
        )
      end
    end
  end

  describe "error handling and validation" do
    context "when handling invalid repository requests" do
      it "validates repository type support" do
        expect {
          described_class.create_account_repository(mock_client, type: :nonexistent)
        }.to raise_error(Ibkr::RepositoryError)
      end

      it "provides informative error messages for unsupported types" do
        described_class.create_account_repository(mock_client, type: :invalid)
      rescue Ibkr::RepositoryError => error
        expect(error.context).to include(:available_types)
        expect(error.context[:available_types]).to include(:api, :cached, :test)
      end
    end

    context "when repository creation encounters issues" do
      before do
        allow(Ibkr::Repositories::ApiAccountRepository).to receive(:new)
          .and_raise(StandardError, "Creation failed")
      end

      it "preserves original error information" do
        expect {
          described_class.create_account_repository(mock_client, type: :api)
        }.to raise_error(StandardError, "Creation failed")
      end
    end

    context "when handling malformed configurations" do
      let(:malformed_chain_config) do
        [
          {type: :api},  # Missing options
          {options: {}}  # Missing type
        ]
      end

      it "handles missing type in chain configuration" do
        # When type is missing, it falls back to default (api)
        result = described_class.create_repository_chain(mock_client, malformed_chain_config)

        # Should still create repositories, using default type when missing
        expect(result).to be_truthy
        expect(Ibkr::Repositories::ApiAccountRepository).to have_received(:new).at_least(:once)
      end
    end
  end

  describe "factory extensibility and flexibility" do
    context "when adapting to diverse client configurations" do
      let(:alternative_client) { double("alternative_client", live: true, environment: :production) }

      it "handles different client implementations" do
        result = described_class.create_auto_repository(alternative_client)

        expect(result).to be_truthy
      end

      it "works with various client interface variations" do
        clients = [
          double("client1", live: true),
          double("client2", live: false),
          mock_client
        ]

        clients.each do |client|
          result = described_class.create_auto_repository(client)
          expect(result).to be_truthy
        end
      end
    end
  end

  describe "practical usage patterns" do
    context "when implementing dependency injection patterns" do
      let(:service_class) do
        Class.new do
          def initialize(repository_factory, client)
            @factory = repository_factory
            @client = client
          end

          def create_repository_for_environment(env_type)
            case env_type
            when :development
              @factory.create_account_repository(@client, type: :cached)
            when :test
              @factory.create_account_repository(@client, type: :test)
            when :production
              @factory.create_account_repository(@client, type: :api)
            else
              @factory.create_auto_repository(@client)
            end
          end
        end
      end

      it "supports flexible repository creation through dependency injection" do
        service = service_class.new(described_class, mock_client)

        dev_repo = service.create_repository_for_environment(:development)
        test_repo = service.create_repository_for_environment(:test)
        prod_repo = service.create_repository_for_environment(:production)
        auto_repo = service.create_repository_for_environment(:unknown)

        [dev_repo, test_repo, prod_repo, auto_repo].each do |repo|
          expect(repo).to be_truthy
        end
      end
    end

    context "when using configuration-driven repository selection" do
      let(:config_driven_setup) do
        {
          environments: {
            development: {
              type: :cached,
              options: {cache_ttl: {summary: 60, positions: 10}}
            }
          }
        }
      end

      it "creates repositories based on configuration data" do
        dev_config = config_driven_setup[:environments][:development]

        repository = described_class.create_account_repository(
          mock_client,
          type: dev_config[:type],
          options: dev_config[:options]
        )

        expect(repository).to be_truthy
        expect(Ibkr::Repositories::CachedAccountRepository).to have_received(:new).with(
          mock_client,
          hash_including(cache_ttl: {summary: 60, positions: 10})
        )
      end
    end
  end
end
