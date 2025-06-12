class CommodityReferenceLoader
  require 'csv'
  
  def self.load_from_csv(file_path)
    new.load_from_csv(file_path)
  end
  
  def load_from_csv(file_path)
    csv_data = CSV.read(file_path, headers: true)
    
    # Crear referencias sin embeddings primero
    references = []
    
    ActiveRecord::Base.transaction do
      # Limpiar datos existentes
      CommodityReference.delete_all
      
      csv_data.each do |row|
        reference = CommodityReference.create!(
          global_comm_code_desc: row['GLOBAL_COMM_CODE_DESC'],
          level1_desc: row['LEVEL1_DESC'],
          level2_desc: row['LEVEL2_DESC'],
          level3_desc: row['LEVEL3_DESC'],
          infinex_scope_status: row['Infinex Scope Status']
        )
        
        references << reference
      end
    end
    
    # Programar la generación de embeddings para ejecutarse en segundo plano
    CommodityEmbeddingsUpdaterJob.perform_later
    
    { success: true, count: CommodityReference.count }
  rescue => e
    Rails.logger.error("Error loading commodity references: #{e.message}")
    { success: false, error: e.message }
  end
  
  def generate_embeddings_for_all(references)
    # Procesar en lotes más grandes para reducir llamadas a la API
    references.each_slice(50) do |batch|
      descriptions = batch.map { |record| record.level3_desc } # CAMBIO: level3_desc
      
      # Generar embeddings para este lote
      embeddings = OpenaiService.get_embeddings(descriptions)
      
      # Actualizar cada registro con su embedding correspondiente en una sola transacción
      ActiveRecord::Base.transaction do
        batch.each_with_index do |record, index|
          record.update(embedding: embeddings[index])
        end
      end
    end
  end
end