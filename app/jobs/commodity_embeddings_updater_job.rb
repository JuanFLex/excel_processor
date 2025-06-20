class CommodityEmbeddingsUpdaterJob < ApplicationJob
  queue_as :default
  
  def perform
    # Encontrar referencias sin embeddings
    references_without_embeddings = CommodityReference.where('embedding IS NULL OR embedding = ?', '{}')
    
    if references_without_embeddings.exists?
      Rails.logger.info "Updating embeddings for #{references_without_embeddings.count} references without embeddings..."
      
      # Procesar en lotes
      references_without_embeddings.find_in_batches(batch_size: 50) do |batch|
        descriptions = batch.map { |record| record.level3_desc }
        
        # Generar embeddings para este lote
        embeddings = OpenaiService.get_embeddings(descriptions)
        
        # Actualizar cada registro con su embedding correspondiente
        ActiveRecord::Base.transaction do
          batch.each_with_index do |record, index|
            record.update(embedding: embeddings[index])
          end
        end
      end
      
      Rails.logger.info "Embeddings updated successfully."
    else
      Rails.logger.info "No references without embeddings to update."
    end
  end
end