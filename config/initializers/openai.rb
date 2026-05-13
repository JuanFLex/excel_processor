require "openai"

OpenAI.configure do |config|
  config.access_token = Rails.application.credentials.dig(:openai, :api_key)

  # Configuración para endpoint corporativo de Flex (Azure OpenAI compatible)
  # NOTA: No configuramos uri_base aquí porque cada operación necesita su propio
  # deployment en la URL. Los clientes se crean en OpenaiService con URIs específicos.
  config.api_type = :azure
  config.api_version = "2025-03-01-preview"

  config.request_timeout = 120 # Aumentar timeout para requests más largos
end

# SSL bypass para servidores sin certificados instalados
if ENV['OPENAI_SSL_BYPASS'] == 'true'
  require 'openssl'
  
  # Configurar SSL bypass globalmente para todas las conexiones HTTPS
  OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_mode] = OpenSSL::SSL::VERIFY_NONE
  
  Rails.logger.info "🔓 [SSL] OpenAI SSL verification disabled via OPENAI_SSL_BYPASS"
end