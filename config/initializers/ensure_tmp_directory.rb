Rails.application.config.after_initialize do
  # Asegurar que el directorio tmp existe
  FileUtils.mkdir_p(Rails.root.join('tmp'))
  
  # Asegurar que el directorio storage existe (para guardar los archivos procesados)
  FileUtils.mkdir_p(Rails.root.join('storage'))
end