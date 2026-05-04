ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Set test environment variables
ENV['MOCK_OPENAI'] = 'true'
ENV['MOCK_SQL_SERVER'] = 'true'

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # fixtures :all  # Comentado para evitar conflictos de fixtures

    # Add more helper methods to be used by all tests here...
    
    # Limpiar base de datos antes de cada test para evitar duplicados
    setup do
      User.delete_all if defined?(User)
    end

    # Helper method to create test user
    def create_test_user(email: "test@example.com", password: "password123", admin: false)
      User.create!(
        email: email,
        password: password,
        password_confirmation: password,
        admin: admin
      )
    end

    # Helper method to create admin user
    def create_admin_user(email: "admin@example.com", password: "password123")
      create_test_user(email: email, password: password, admin: true)
    end
  end
end

# Integration test helpers for authentication
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup_test_user
    @user = create_test_user
    sign_in @user
    @user
  end

  def setup_admin_user  
    @admin = create_admin_user
    sign_in @admin
    @admin
  end
end
