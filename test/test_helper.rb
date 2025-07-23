ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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
  end
end
