require "openai"

OpenAI.configure do |config|
  config.access_token = Rails.application.credentials.dig(:openai, :api_key)
  config.organization_id = Rails.application.credentials.dig(:openai, :organization_id) # opcional
  config.request_timeout = 120 # Aumentar timeout para requests más largos
end