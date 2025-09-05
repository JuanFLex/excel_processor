Rails.application.console do
  # Cargar helper de análisis de commodities
  require Rails.root.join('lib', 'commodity_analyzer_console.rb')
  
  # Auto-cargar módulos de análisis
  Dir[Rails.root.join('app', 'services', 'commodity_analysis', '*.rb')].each { |f| require f }
end