class CommodityReference < ApplicationRecord
  validates :level3_desc, presence: true
  
  #Metodo para generar el texto completo para embeddings
  def full_text_for_embedding
    parts = [
      global_comm_code_desc,
      level1_desc,
      level2_desc,
      level3_desc,
      keyword,
      mfr
    ].compact.reject(&:blank?)
    parts.join(' ')
  end

  # Método para encontrar el commodity más similar a una descripción dada
  def self.find_most_similar(description_embedding, limit = 1)
    return [] if description_embedding.nil?
    
    # Convertir embedding del parámetro a un array de Ruby
    query_embedding = description_embedding
    
    # Ordenamos por similitud de coseno (mayor similitud primero)
    # Esto se hace calculando el producto punto entre los vectores normalizados
    records = all.sort_by do |record|
      next -Float::INFINITY unless record.embedding.is_a?(Array)
      
      # Calcular similitud de coseno manualmente
      dot_product = 0
      record_embedding = record.embedding
      record_embedding.each_with_index do |val, i|
        dot_product += val * query_embedding[i]
      end
      
      # Magnitud (normalizada) = 1, por lo que la similitud es simplemente el producto punto
      -dot_product # Negativo para ordenar por mayor similitud primero
    end
    
    records.first(limit)
  end

  # NUEVO: Método para buscar por commodity exacto
  def self.find_by_commodity_exact(commodity_name)
    where("LOWER(level3_desc) = LOWER(?)", commodity_name.to_s.strip).first
  end

  # NUEVO: Método para buscar scope por commodity
  def self.scope_for_commodity(commodity_name)
    record = find_by_commodity_exact(commodity_name)
    return 'Out of scope' unless record
    
    record.infinex_scope_status == 'In Scope' ? 'In scope' : 'Out of scope'
  end  
end