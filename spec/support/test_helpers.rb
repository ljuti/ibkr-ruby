# frozen_string_literal: true

module TestHelpers
  # Helper methods for setting up test state using proper encapsulation
  module ClientTestHelper
    # Set up a client in authenticated state for testing
    def setup_authenticated_client(client, oauth_client:, accounts: ["DU123456"], active_account: nil)
      active_account ||= accounts.first

      # Mock the oauth client
      allow(client).to receive(:oauth_client).and_return(oauth_client)

      # Ensure oauth_client has the methods needed for authentication
      unless oauth_client.respond_to?(:authenticate)
        allow(oauth_client).to receive(:authenticate).and_return(true)
      end
      unless oauth_client.respond_to?(:authenticated?)
        allow(oauth_client).to receive(:authenticated?).and_return(true)
      end
      unless oauth_client.respond_to?(:initialize_session)
        allow(oauth_client).to receive(:initialize_session).and_return(true)
      end
      unless oauth_client.respond_to?(:get)
        allow(oauth_client).to receive(:get)
          .with("/v1/api/iserver/accounts")
          .and_return({"accounts" => accounts})
      end

      # Perform authentication to set up state properly
      client.authenticate

      # Set active account if different from default
      if active_account != accounts.first && accounts.include?(active_account)
        client.set_active_account(active_account)
      end

      client
    end
  end

  # Helper for Accounts service testing
  module AccountsTestHelper
    # Check if service has expected client reference
    # Since @_client is private, we test behavior instead of state
    def expect_client_reference(service, expected_client)
      # Test that the service uses the expected client by checking behavior
      expect(service.account_id).to eq(expected_client.account_id)
    end
  end
end

RSpec.configure do |config|
  config.include TestHelpers::ClientTestHelper
  config.include TestHelpers::AccountsTestHelper
end
