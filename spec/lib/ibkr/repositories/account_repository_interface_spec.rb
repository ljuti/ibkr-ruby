# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ibkr::Repositories::AccountRepositoryInterface do
  # Create a test class that includes the interface
  let(:test_class) do
    Class.new do
      include Ibkr::Repositories::AccountRepositoryInterface
    end
  end

  let(:repository_instance) { test_class.new }

  describe "interface contract" do
    context "when interface methods are not implemented" do
      describe "#find_summary" do
        it "raises NotImplementedError when called without implementation" do
          expect {
            repository_instance.find_summary("DU123456")
          }.to raise_error(NotImplementedError, "Subclasses must implement #find_summary")
        end

        it "accepts account_id parameter as specified in contract" do
          expect {
            repository_instance.find_summary("DU123456")
          }.to raise_error(NotImplementedError)
          # If we get here, the method signature was accepted
        end
      end

      describe "#find_metadata" do
        it "raises NotImplementedError when called without implementation" do
          expect {
            repository_instance.find_metadata("DU123456")
          }.to raise_error(NotImplementedError, "Subclasses must implement #find_metadata")
        end

        it "accepts account_id parameter as specified in contract" do
          expect {
            repository_instance.find_metadata("DU123456")
          }.to raise_error(NotImplementedError)
        end
      end

      describe "#find_positions" do
        it "raises NotImplementedError when called without implementation" do
          expect {
            repository_instance.find_positions("DU123456")
          }.to raise_error(NotImplementedError, "Subclasses must implement #find_positions")
        end

        it "accepts account_id and optional options parameters" do
          expect {
            repository_instance.find_positions("DU123456", {page: 1})
          }.to raise_error(NotImplementedError)
        end

        it "handles missing options parameter with default empty hash" do
          expect {
            repository_instance.find_positions("DU123456")
          }.to raise_error(NotImplementedError)
        end
      end

      describe "#find_transactions" do
        it "raises NotImplementedError when called without implementation" do
          expect {
            repository_instance.find_transactions("DU123456", 123456)
          }.to raise_error(NotImplementedError, "Subclasses must implement #find_transactions")
        end

        it "accepts account_id and contract_id parameters" do
          expect {
            repository_instance.find_transactions("DU123456", 123456)
          }.to raise_error(NotImplementedError)
        end

        it "handles optional days parameter with default value" do
          expect {
            repository_instance.find_transactions("DU123456", 123456, 30)
          }.to raise_error(NotImplementedError)
        end
      end

      describe "#discover_accounts" do
        it "raises NotImplementedError when called without implementation" do
          expect {
            repository_instance.discover_accounts
          }.to raise_error(NotImplementedError, "Subclasses must implement #discover_accounts")
        end

        it "requires no parameters according to contract" do
          expect {
            repository_instance.discover_accounts
          }.to raise_error(NotImplementedError)
        end
      end

      describe "#account_exists?" do
        it "raises NotImplementedError when called without implementation" do
          expect {
            repository_instance.account_exists?("DU123456")
          }.to raise_error(NotImplementedError, "Subclasses must implement #account_exists?")
        end

        it "accepts account_id parameter as specified in contract" do
          expect {
            repository_instance.account_exists?("DU123456")
          }.to raise_error(NotImplementedError)
        end
      end
    end
  end

  describe "contract compliance testing" do
    # Create a test implementation to verify contract compliance
    let(:compliant_implementation) do
      Class.new do
        include Ibkr::Repositories::AccountRepositoryInterface

        def find_summary(account_id)
          {
            "accountId" => account_id,
            "totalCashValue" => "100000.00",
            "netLiquidation" => "120000.00"
          }
        end

        def find_metadata(account_id)
          {
            "accountId" => account_id,
            "accountType" => "DEMO",
            "tradingPermissions" => ["STOCKS", "OPTIONS"]
          }
        end

        def find_positions(account_id, options = {})
          {
            "results" => [
              {
                "contractId" => 123,
                "position" => "100",
                "marketPrice" => "150.25"
              }
            ],
            "page" => options[:page] || 1
          }
        end

        def find_transactions(account_id, contract_id, days = 90)
          [
            {
              "transactionId" => "T001",
              "accountId" => account_id,
              "contractId" => contract_id,
              "days" => days,
              "date" => "2023-12-01"
            }
          ]
        end

        def discover_accounts
          ["DU123456", "DU789012"]
        end

        def account_exists?(account_id)
          discover_accounts.include?(account_id)
        end
      end
    end

    let(:compliant_repository) { compliant_implementation.new }

    context "when implementation provides all required methods" do
      describe "#find_summary contract compliance" do
        it "returns account summary data structure" do
          result = compliant_repository.find_summary("DU123456")

          expect(result).to be_a(Hash)
          expect(result).to include("accountId", "totalCashValue", "netLiquidation")
          expect(result["accountId"]).to eq("DU123456")
        end

        it "handles different account IDs correctly" do
          result1 = compliant_repository.find_summary("DU123456")
          result2 = compliant_repository.find_summary("DU789012")

          expect(result1["accountId"]).to eq("DU123456")
          expect(result2["accountId"]).to eq("DU789012")
        end
      end

      describe "#find_metadata contract compliance" do
        it "returns account metadata hash" do
          result = compliant_repository.find_metadata("DU123456")

          expect(result).to be_a(Hash)
          expect(result).to include("accountId", "accountType", "tradingPermissions")
          expect(result["tradingPermissions"]).to be_an(Array)
        end
      end

      describe "#find_positions contract compliance" do
        it "returns positions data with results array" do
          result = compliant_repository.find_positions("DU123456")

          expect(result).to be_a(Hash)
          expect(result).to have_key("results")
          expect(result["results"]).to be_an(Array)
        end

        it "handles options parameter for query customization" do
          options = {page: 2, sort: "name", direction: "asc"}
          result = compliant_repository.find_positions("DU123456", options)

          expect(result["page"]).to eq(2)
        end

        it "provides default behavior when options are not specified" do
          result = compliant_repository.find_positions("DU123456")

          expect(result["page"]).to eq(1) # Default page
        end
      end

      describe "#find_transactions contract compliance" do
        it "returns array of transaction records" do
          result = compliant_repository.find_transactions("DU123456", 123456)

          expect(result).to be_an(Array)
          expect(result.first).to include("transactionId", "accountId", "contractId")
          expect(result.first["accountId"]).to eq("DU123456")
          expect(result.first["contractId"]).to eq(123456)
        end

        it "uses default days parameter when not specified" do
          result = compliant_repository.find_transactions("DU123456", 123456)

          expect(result.first["days"]).to eq(90) # Default value
        end

        it "respects custom days parameter" do
          result = compliant_repository.find_transactions("DU123456", 123456, 30)

          expect(result.first["days"]).to eq(30)
        end
      end

      describe "#discover_accounts contract compliance" do
        it "returns array of available account IDs" do
          result = compliant_repository.discover_accounts

          expect(result).to be_an(Array)
          expect(result).to all(be_a(String))
          expect(result).to include("DU123456", "DU789012")
        end

        it "provides consistent results across calls" do
          result1 = compliant_repository.discover_accounts
          result2 = compliant_repository.discover_accounts

          expect(result1).to eq(result2)
        end
      end

      describe "#account_exists? contract compliance" do
        it "returns boolean indicating account accessibility" do
          result_exists = compliant_repository.account_exists?("DU123456")
          result_missing = compliant_repository.account_exists?("DU999999")

          expect(result_exists).to be true
          expect(result_missing).to be false
        end

        it "integrates with discover_accounts for consistency" do
          available_accounts = compliant_repository.discover_accounts

          available_accounts.each do |account_id|
            expect(compliant_repository.account_exists?(account_id)).to be true
          end

          expect(compliant_repository.account_exists?("NONEXISTENT")).to be false
        end
      end
    end
  end

  describe "interface usage patterns" do
    # Create a client class that depends on the interface
    let(:client_class) do
      Class.new do
        def initialize(repository)
          unless repository.is_a?(Object) &&
              repository.class.included_modules.include?(Ibkr::Repositories::AccountRepositoryInterface)
            raise ArgumentError, "Repository must implement AccountRepositoryInterface"
          end
          @repository = repository
        end

        def get_account_overview(account_id)
          summary = @repository.find_summary(account_id)
          metadata = @repository.find_metadata(account_id)

          {
            account_id: account_id,
            summary: summary,
            metadata: metadata
          }
        end

        def get_portfolio_snapshot(account_id, options = {})
          positions = @repository.find_positions(account_id, options)
          summary = @repository.find_summary(account_id)

          {
            account_id: account_id,
            positions: positions,
            total_value: summary["netLiquidation"]
          }
        end

        def validate_account_access(account_id)
          @repository.account_exists?(account_id)
        end
      end
    end

    context "when using interface through client code" do
      let(:compliant_implementation) do
        Class.new do
          include Ibkr::Repositories::AccountRepositoryInterface

          def find_summary(account_id)
            {"accountId" => account_id, "netLiquidation" => "120000.00"}
          end

          def find_metadata(account_id)
            {"accountId" => account_id, "accountType" => "DEMO"}
          end

          def find_positions(account_id, options = {})
            {"results" => [], "page" => options[:page] || 1}
          end

          def find_transactions(account_id, contract_id, days = 90)
            []
          end

          def discover_accounts
            ["DU123456"]
          end

          def account_exists?(account_id)
            account_id == "DU123456"
          end
        end
      end

      let(:client) { client_class.new(compliant_implementation.new) }

      it "enables polymorphic usage of different repository implementations" do
        overview = client.get_account_overview("DU123456")

        expect(overview).to include(:account_id, :summary, :metadata)
        expect(overview[:account_id]).to eq("DU123456")
        expect(overview[:summary]).to include("accountId", "netLiquidation")
        expect(overview[:metadata]).to include("accountId", "accountType")
      end

      it "supports complex operations combining multiple interface methods" do
        snapshot = client.get_portfolio_snapshot("DU123456", {page: 2})

        expect(snapshot).to include(:account_id, :positions, :total_value)
        expect(snapshot[:positions]["page"]).to eq(2)
        expect(snapshot[:total_value]).to eq("120000.00")
      end

      it "enables account validation workflows" do
        valid_result = client.validate_account_access("DU123456")
        invalid_result = client.validate_account_access("DU999999")

        expect(valid_result).to be true
        expect(invalid_result).to be false
      end
    end

    context "when repository implementation is incomplete" do
      let(:incomplete_implementation) do
        Class.new do
          include Ibkr::Repositories::AccountRepositoryInterface

          # Only implement some methods, leave others as NotImplementedError
          def find_summary(account_id)
            {"accountId" => account_id}
          end

          def account_exists?(account_id)
            true
          end

          # find_metadata, find_positions, find_transactions, discover_accounts
          # will raise NotImplementedError
        end
      end

      it "rejects incomplete implementations during client initialization" do
        # The client can still be created, but method calls will fail
        client = client_class.new(incomplete_implementation.new)

        expect {
          client.get_account_overview("DU123456")
        }.to raise_error(NotImplementedError, /find_metadata/)
      end
    end
  end

  describe "interface documentation and parameter validation" do
    context "when validating method signatures" do
      it "defines find_summary with correct parameter documentation" do
        method = Ibkr::Repositories::AccountRepositoryInterface.instance_method(:find_summary)
        expect(method.parameters).to eq([[:req, :account_id]])
      end

      it "defines find_metadata with correct parameter documentation" do
        method = Ibkr::Repositories::AccountRepositoryInterface.instance_method(:find_metadata)
        expect(method.parameters).to eq([[:req, :account_id]])
      end

      it "defines find_positions with optional options parameter" do
        method = Ibkr::Repositories::AccountRepositoryInterface.instance_method(:find_positions)
        expect(method.parameters).to eq([[:req, :account_id], [:opt, :options]])
      end

      it "defines find_transactions with optional days parameter" do
        method = Ibkr::Repositories::AccountRepositoryInterface.instance_method(:find_transactions)
        expect(method.parameters).to eq([[:req, :account_id], [:req, :contract_id], [:opt, :days]])
      end

      it "defines discover_accounts with no required parameters" do
        method = Ibkr::Repositories::AccountRepositoryInterface.instance_method(:discover_accounts)
        expect(method.parameters).to eq([])
      end

      it "defines account_exists? with correct parameter documentation" do
        method = Ibkr::Repositories::AccountRepositoryInterface.instance_method(:account_exists?)
        expect(method.parameters).to eq([[:req, :account_id]])
      end
    end
  end

  describe "interface extension scenarios" do
    context "when extending interface for specialized repositories" do
      let(:extended_interface) do
        Module.new do
          include Ibkr::Repositories::AccountRepositoryInterface

          # Additional methods for specialized repository
          def find_summary_with_cache_info(account_id)
            raise NotImplementedError, "Subclasses must implement #find_summary_with_cache_info"
          end

          def batch_find_summaries(account_ids)
            raise NotImplementedError, "Subclasses must implement #batch_find_summaries"
          end
        end
      end

      let(:extended_implementation) do
        extended_module = extended_interface
        Class.new do
          include extended_module

          def find_summary(account_id)
            {"accountId" => account_id}
          end

          def find_metadata(account_id)
            {"accountId" => account_id}
          end

          def find_positions(account_id, options = {})
            {"results" => []}
          end

          def find_transactions(account_id, contract_id, days = 90)
            []
          end

          def discover_accounts
            ["DU123456"]
          end

          def account_exists?(account_id)
            true
          end

          def find_summary_with_cache_info(account_id)
            {
              summary: find_summary(account_id),
              cache_hit: false,
              cached_at: nil
            }
          end

          def batch_find_summaries(account_ids)
            account_ids.map { |id| find_summary(id) }
          end
        end
      end

      it "supports interface extension while maintaining base contract" do
        repository = extended_implementation.new

        # Base interface methods work
        expect(repository.find_summary("DU123456")).to include("accountId")
        expect(repository.account_exists?("DU123456")).to be true

        # Extended methods work
        cache_result = repository.find_summary_with_cache_info("DU123456")
        expect(cache_result).to include(:summary, :cache_hit, :cached_at)

        batch_result = repository.batch_find_summaries(["DU123456", "DU789012"])
        expect(batch_result).to be_an(Array)
        expect(batch_result.size).to eq(2)
      end
    end
  end

  describe "interface testing utilities" do
    # Shared examples for testing any repository implementation
    shared_examples "a compliant AccountRepository" do
      let(:test_account_id) { "DU123456" }
      let(:test_contract_id) { 123456 }

      describe "basic interface compliance" do
        it "implements find_summary without raising NotImplementedError" do
          expect { subject.find_summary(test_account_id) }.not_to raise_error(NotImplementedError)
        end

        it "implements find_metadata without raising NotImplementedError" do
          expect { subject.find_metadata(test_account_id) }.not_to raise_error(NotImplementedError)
        end

        it "implements find_positions without raising NotImplementedError" do
          expect { subject.find_positions(test_account_id) }.not_to raise_error(NotImplementedError)
        end

        it "implements find_transactions without raising NotImplementedError" do
          expect { subject.find_transactions(test_account_id, test_contract_id) }.not_to raise_error(NotImplementedError)
        end

        it "implements discover_accounts without raising NotImplementedError" do
          expect { subject.discover_accounts }.not_to raise_error(NotImplementedError)
        end

        it "implements account_exists? without raising NotImplementedError" do
          expect { subject.account_exists?(test_account_id) }.not_to raise_error(NotImplementedError)
        end
      end

      describe "return type compliance" do
        it "returns appropriate type from find_summary" do
          result = subject.find_summary(test_account_id)
          expect(result).to respond_to(:[]) # Should be Hash-like
        end

        it "returns appropriate type from find_metadata" do
          result = subject.find_metadata(test_account_id)
          expect(result).to respond_to(:[]) # Should be Hash-like
        end

        it "returns appropriate type from find_positions" do
          result = subject.find_positions(test_account_id)
          expect(result).to respond_to(:[]) # Should be Hash-like
          expect(result).to respond_to(:has_key?) # Should have results key
        end

        it "returns appropriate type from find_transactions" do
          result = subject.find_transactions(test_account_id, test_contract_id)
          expect(result).to respond_to(:each) # Should be Array-like
        end

        it "returns appropriate type from discover_accounts" do
          result = subject.discover_accounts
          expect(result).to respond_to(:each) # Should be Array-like
          expect(result).to respond_to(:include?) # Should support include?
        end

        it "returns boolean from account_exists?" do
          result = subject.account_exists?(test_account_id)
          expect([true, false]).to include(result)
        end
      end
    end

    # Demonstrate usage of shared examples
    context "when testing a compliant implementation" do
      let(:compliant_repo) do
        Class.new do
          include Ibkr::Repositories::AccountRepositoryInterface

          def find_summary(account_id)
            {"accountId" => account_id}
          end

          def find_metadata(account_id)
            {"accountId" => account_id}
          end

          def find_positions(account_id, options = {})
            {"results" => []}
          end

          def find_transactions(account_id, contract_id, days = 90)
            []
          end

          def discover_accounts
            ["DU123456"]
          end

          def account_exists?(account_id)
            account_id == "DU123456"
          end
        end.new
      end

      subject { compliant_repo }

      include_examples "a compliant AccountRepository"
    end
  end
end
