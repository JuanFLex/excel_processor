require "openai"

OpenAI.configure do |config|
  config.access_token = Rails.application.credentials.dig(:openai, :api_key)
  config.organization_id = Rails.application.credentials.dig(:openai, :organization_id) # opcional
  config.request_timeout = 120 # Aumentar timeout para requests más largos
end

# SSL bypass para servidores sin certificados instalados
if ENV['OPENAI_SSL_BYPASS'] == 'true'
  require 'openssl'
  
  # Configurar SSL bypass globalmente para todas las conexiones HTTPS
  OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_mode] = OpenSSL::SSL::VERIFY_NONE
  
  Rails.logger.info "🔓 [SSL] OpenAI SSL verification disabled via OPENAI_SSL_BYPASS"
end