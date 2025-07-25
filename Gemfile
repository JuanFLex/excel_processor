# Gemfile
source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.0"

# Rails default gems
gem "rails", "~> 7.1.0"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", "~> 6.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]
gem "bootsnap", require: false
gem "tailwindcss-rails"
gem "haml-rails", "~> 2.1"
gem "devise", "~> 4.9"          # Autenticación de usuarios

gem "activerecord-sqlserver-adapter", "~> 7.0"
gem "tiny_tds", "~> 2.1"

#graficas
gem 'chartkick'

# Excel processing
gem "roo", "~> 2.10.0"          # Para leer archivos Excel
gem "caxlsx", "~> 4.0"           # Para crear archivos Excel
gem "caxlsx_rails", "~> 0.6"     # Integración de axlsx con Rails

# OpenAI integration
gem "ruby-openai", "~> 6.0"      # Cliente Ruby para OpenAI

# Vector embeddings and similarity
gem "matrix", "~> 0.4.2"         # Para operaciones con vectores
gem "narray", "~> 0.6.1"         # Para cálculos de matrices más eficientes
gem "sidekiq", "~> 7.1"          # Para procesar tareas en segundo plano

#para paginacion
gem "kaminari", "~> 1.2"

# Para testing
group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
  
end

group :development do
  gem "web-console"
  gem "rubocop", "~> 1.56", require: false
  gem "rubocop-rails", "~> 2.21", require: false
  gem "annotate", "~> 3.2"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end