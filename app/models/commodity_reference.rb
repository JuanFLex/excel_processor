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
  
  #Metodo para generar el texto completo para embeddings con formato estructurado
  def full_text_for_embedding
    # Construir jerarquía de categorías
    category_hierarchy = [level1_desc, level2_desc].compact.reject(&:blank?).join(' > ')
    
    # Usar descripción expandida si está disponible, sino la normal
    description = level3_desc_expanded.present? ? level3_desc_expanded : level3_desc
    
    # Construir el texto estructurado
    embedding_parts = []
    
    # Commodity principal
    if level3_desc.present?
      commodity_name = level3_desc.gsub(/[^A-Za-z0-9\s,]/, '').gsub(/\s+/, '_').upcase
      embedding_parts << "Commodity: #{commodity_name}"
    end
    
    # Jerarquía de categorías
    if category_hierarchy.present?
      embedding_parts << "Category Hierarchy: #{category_hierarchy}"
    end
    
    # Descripción detallada
    if description.present?
      embedding_parts << "Description: #{description}"
    end
    
    # Palabras clave
    if keyword.present?
      embedding_parts << "Keywords: #{keyword}"
    end
    
    # Fabricantes típicos (extraídos del campo mfr si existe)
    if mfr.present?
      embedding_parts << "Typical Manufacturers: #{mfr}"
    end
    
    # MPNs típicos por fabricante
    if typical_mpn_by_manufacturer.present?
      embedding_parts << "Typical MPNs by Manufacturer: #{typical_mpn_by_manufacturer}"
    end
    
    # Código global del commodity como contexto adicional
    if global_comm_code_desc.present? && global_comm_code_desc != level3_desc
      embedding_parts << "Global Code: #{global_comm_code_desc}"
    end
    
    embedding_parts.join("\n")
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
    
    # FIX: Usar comparación case-insensitive para manejar variaciones en capitalización
    record.infinex_scope_status&.downcase == 'in scope' ? 'In scope' : 'Out of scope'
  end
  
  # Scope para búsqueda global
  def self.search(query)
    return all if query.blank?
    
    where(
      "global_comm_code_desc ILIKE ? OR level1_desc ILIKE ? OR level2_desc ILIKE ? OR level3_desc ILIKE ? OR level3_desc_expanded ILIKE ? OR typical_mpn_by_manufacturer ILIKE ? OR keyword ILIKE ? OR mfr ILIKE ?",
      "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%"
    )
  end
  
  # Método para forzar regeneración de embedding
  def regenerate_embedding!
    Rails.logger.info "🔄 [EMBEDDING] Force regenerating embedding for commodity reference #{id}"
    
    full_text = full_text_for_embedding
    if full_text.present?
      new_embedding = OpenaiService.get_embedding_for_text(full_text)
      if new_embedding
        update_column(:embedding, new_embedding)
        Rails.logger.info "✅ [EMBEDDING] Successfully regenerated embedding for commodity reference #{id}"
        true
      else
        Rails.logger.error "❌ [EMBEDDING] Failed to generate new embedding for commodity reference #{id}"
        false
      end
    else
      Rails.logger.warn "⚠️ [EMBEDDING] No text available for embedding generation for commodity reference #{id}"
      false
    end
  end
  
  private
  
  def regenerate_embedding_if_needed
    if saved_change_to_keyword? || saved_change_to_mfr? || saved_change_to_infinex_scope_status?
      changes_made = []
      changes_made << "keyword" if saved_change_to_keyword?
      changes_made << "manufacturer" if saved_change_to_mfr?
      changes_made << "scope status" if saved_change_to_infinex_scope_status?
      
      Rails.logger.info "🔄 [EMBEDDING] Regenerating embedding for commodity reference #{id} due to #{changes_made.join(', ')} change"
      
      # Regenerar embedding usando OpenAI
      full_text = full_text_for_embedding
      if full_text.present?
        new_embedding = OpenaiService.get_embedding_for_text(full_text)
        if new_embedding
          update_column(:embedding, new_embedding)
          Rails.logger.info "✅ [EMBEDDING] Successfully regenerated embedding for commodity reference #{id}"
        else
          Rails.logger.error "❌ [EMBEDDING] Failed to generate new embedding for commodity reference #{id}"
        end
      end
    end
  end
end