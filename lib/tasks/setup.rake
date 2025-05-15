namespace :app do
  desc "Configurar aplicación con datos iniciales"
  task setup: :environment do
    # Verificar si ya existen commodities
    if CommodityReference.count > 0
      puts "Ya existen referencias de commodities. Omitiendo carga inicial."
    else
      # Buscar archivo CSV de commodities
      csv_path = Rails.root.join('db', 'sample_data', 'commodity_references.csv')
      
      if File.exist?(csv_path)
        puts "Cargando referencias de commodities..."
        result = CommodityReferenceLoader.load_from_csv(csv_path)
        
        if result[:success]
          puts "Se cargaron #{result[:count]} referencias de commodities."
        else
          puts "Error al cargar referencias: #{result[:error]}"
        end
      else
        puts "Archivo CSV de commodities no encontrado en #{csv_path}"
        puts "Ejecutando rake db:seed para crear datos de muestra..."
        Rake::Task["db:seed"].invoke
      end
    end
    
    # Crear directorios necesarios
    %w[tmp storage log].each do |dir|
      path = Rails.root.join(dir)
      unless Dir.exist?(path)
        puts "Creando directorio: #{path}"
        FileUtils.mkdir_p(path)
      end
    end
    
    puts "Configuración completada!"
  end
end