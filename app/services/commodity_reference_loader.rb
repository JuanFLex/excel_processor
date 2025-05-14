class CommodityReferenceLoader
  require 'csv'
  
  def self.load_from_csv(file_path)
    new.load_from_csv(file_path)
  end
  
  def load_from_csv(file_path)
    csv_data = CSV.read(file_path, headers: true)
    
    ActiveRecord::Base.transaction do
      # Limpiar datos existentes
      CommodityReference.delete_all
      
      csv_data.each do |row|
        CommodityReference.create!(
          global_comm_code_desc: row['GLOBAL_COMM_CODE_DESC'],
          level1_desc: row['LEVEL1_DESC'],
          level2_desc: row['LEVEL2_DESC'],
          level3_desc: row['LEVEL3_DESC'],
          infinex_scope_status: row['Infinex Scope Status']
        )
      end
    end
    
    # Generar embeddings para todos los registros
    generate_embeddings_for_all
    
    { success: true, count: CommodityReference.count }
  rescue => e
    Rails.logger.error("Error loading commodity references: #{e.message}")
    { success: false, error: e.message }
  end
  
  def generate_embeddings_for_all
    # Procesamos en lotes para no sobrecargar la API de OpenAI
    CommodityReference.find_in_batches(batch_size: 100) do |batch|
      descriptions = batch.map { |record| record.level2_desc }
      
      # Generar embeddings para este lote
      embeddings = OpenaiService.get_embeddings(descriptions)
      
      # Actualizar cada registro con su embedding correspondiente
      batch.each_with_index do |record, index|
        record.update(embedding: embeddings[index])
      end
    end
  end
end