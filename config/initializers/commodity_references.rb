Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.table_exists?('commodity_references') && 
     defined?(CommodityReference) && 
     CommodityReference.count == 0
    
    sample_csv_path = Rails.root.join('db', 'sample_data', 'commodity_references.csv')
    
    if File.exist?(sample_csv_path)
      Rails.logger.info "Cargando referencias de commodities iniciales..."
      begin
        CommodityReferenceLoader.load_from_csv(sample_csv_path)
        Rails.logger.info "Referencias de commodities cargadas: #{CommodityReference.count}"
      rescue => e
        Rails.logger.error "Error al cargar referencias de commodities: #{e.message}"
      end
    else
      Rails.logger.warn "No se encontró el archivo de referencias de commodities. Por favor ejecuta rails db:seed"
    end
  end
end