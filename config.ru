require_relative "config/environment"

Rails.application.load_server

if (relative_root = ENV['RAILS_RELATIVE_URL_ROOT'])
  map relative_root do
    run Rails.application
  end
else
  run Rails.application
end
