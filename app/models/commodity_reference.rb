class CommodityReference < ApplicationRecord
  validates :level3_desc, presence: true
  
  # Callback para regenerar embedding cuando se actualiza
  after_update :regenerate_embedding_if_needed
  
  # Valores válidos para scope status
  SCOPE_OPTIONS = [
    'In Scope',
    'Out of Scope', 
    'Under Consideration',
    'Under Development',
    'Under Investigation'
  ].freeze
  
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
  def self.find_by_commodity_exact(commodity_name, column_type = 'level3_desc')
    case column_type.to_s
    when 'global_comm_code_desc'
      where("LOWER(global_comm_code_desc) = LOWER(?)", commodity_name.to_s.strip).first
    else # 'level3_desc'
      where("LOWER(level3_desc) = LOWER(?)", commodity_name.to_s.strip).first
    end
  end

  # NUEVO: Método para buscar scope por commodity
  def self.scope_for_commodity(commodity_name, column_type = 'level3_desc')
    record = find_by_commodity_exact(commodity_name, column_type)
    return 'Out of scope' unless record
    
    record.infinex_scope_status == 'In Scope' ? 'In scope' : 'Out of scope'
  end
  
  # Scope para búsqueda global
  def self.search(query)
    return all if query.blank?
    
    where(
      "global_comm_code_desc ILIKE ? OR level1_desc ILIKE ? OR level2_desc ILIKE ? OR level3_desc ILIKE ? OR keyword ILIKE ? OR mfr ILIKE ?",
      "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%"
    )
  end
  
  private
  
  def regenerate_embedding_if_needed
    if saved_change_to_keyword? || saved_change_to_mfr? || saved_change_to_infinex_scope_status?
      # TODO: Aquí se regeneraría el embedding usando OpenAI
      # Por ahora solo registramos que necesita regeneración
      changes_made = []
      changes_made << "keyword" if saved_change_to_keyword?
      changes_made << "manufacturer" if saved_change_to_mfr?
      changes_made << "scope status" if saved_change_to_infinex_scope_status?
      
      Rails.logger.info "DEMO: Regenerating embedding for commodity reference #{id} due to #{changes_made.join(', ')} change"
    end
  end
end