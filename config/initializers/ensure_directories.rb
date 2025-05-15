Rails.application.config.after_initialize do
  # Asegurar que los directorios necesarios existan
  %w[tmp storage log].each do |dir|
    path = Rails.root.join(dir)
    FileUtils.mkdir_p(path) unless Dir.exist?(path)
  end
end