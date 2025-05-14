class CommodityEmbeddingsUpdaterJob < ApplicationJob
  queue_as :default
  
  def perform
    # Encontrar referencias sin embeddings
    references_without_embeddings = CommodityReference.where('embedding IS NULL OR embedding = ?', '{}')
    
    if references_without_embeddings.exists?
      Rails.logger.info "Actualizando embeddings para #{references_without_embeddings.count} referencias sin embeddings..."
      
      # Procesar en lotes
      references_without_embeddings.find_in_batches(batch_size: 50) do |batch|
        descriptions = batch.map { |record| record.level2_desc }
        
        # Generar embeddings para este lote
        embeddings = OpenaiService.get_embeddings(descriptions)
        
        # Actualizar cada registro con su embedding correspondiente
        ActiveRecord::Base.transaction do
          batch.each_with_index do |record, index|
            record.update(embedding: embeddings[index])
          end
        end
      end
      
      Rails.logger.info "Embeddings actualizados correctamente."
    else
      Rails.logger.info "No hay referencias sin embeddings para actualizar."
    end
  end
end