class CommodityReference < ApplicationRecord
  include SimilarityCalculable
  has_neighbors :embedding_vector
  validates :level3_desc, presence: true
  validates :autograde_scope, inclusion: {
    in: ['In Scope', 'Out of Scope', 'in scope', 'out of scope', 'In scope', 'Out scope'],
    allow_blank: true,
    message: "must be 'In Scope' or 'Out of Scope' (received: '%{value}')"
  }

  # Atributo virtual para similitud de coseno calculada por PostgreSQL
  attr_accessor :cosine_similarity
  
  # Callback para normalizar scope values antes de guardar
  before_save :normalize_scope_values

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
  # Usa pgvector + índice HNSW vía la gema `neighbor` (nearest_neighbors).
  def self.find_most_similar(description_embedding, limit = 1)
    return [] if description_embedding.nil?

    start_time = Time.current

    records = where.not(embedding_vector: nil)
                   .nearest_neighbors(:embedding_vector, description_embedding, distance: "cosine")
                   .limit(limit)
                   .to_a

    # `neighbor` expone la distancia de coseno (0..2) en `neighbor_distance`.
    # Convertimos a similitud de coseno (1 - distance) para mantener el contrato previo.
    records.each { |r| r.cosine_similarity = 1.0 - r.neighbor_distance.to_f }

    elapsed_ms = ((Time.current - start_time) * 1000).round(2)
    Rails.logger.info "⏱️ [TIMING] pgvector cosine similarity search: #{records.size} results in #{elapsed_ms}ms"

    records
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
  def self.scope_for_commodity(commodity_name, column_type = 'level3_desc', auto_mode = false)
    record = find_by_commodity_exact(commodity_name, column_type)
    return 'Out of scope' unless record

    # Si está en modo AUTO, usar autograde_scope; si no, usar infinex_scope_status
    scope_field = auto_mode && record.autograde_scope.present? ?
      record.autograde_scope :
      record.infinex_scope_status

    # Normalizar comparación (case-insensitive)
    return 'Out of scope' if scope_field.blank?

    scope_field.downcase.strip == 'in scope' ? 'In scope' : 'Out of scope'
  end

  # OPTIMIZACIÓN: Buscar múltiples commodities en batch para evitar N+1 queries
  def self.find_commodities_batch(commodity_names, column_type = 'level3_desc')
    return {} if commodity_names.empty?
    
    unique_names = commodity_names.compact.reject(&:blank?).uniq
    commodities_cache = {}
    
    Rails.logger.info "🔍 [COMMODITY BATCH] Loading #{unique_names.size} commodities in batches"
    
    # Procesar en lotes para evitar queries muy grandes
    unique_names.each_slice(ExcelProcessorConfig::BATCH_SIZE).with_index do |batch_names, batch_index|
      Rails.logger.info "🔍 [COMMODITY BATCH] Processing batch #{batch_index + 1} (#{batch_names.size} commodities)"
      
      case column_type.to_s
      when 'global_comm_code_desc'
        # Crear mapeo case-insensitive para global_comm_code_desc
        lower_names = batch_names.map(&:to_s).map(&:strip).map(&:downcase)
        batch_results = where("LOWER(global_comm_code_desc) IN (?)", lower_names)
        
        batch_results.each do |record|
          # Buscar el nombre original que coincide (case-insensitive)
          original_name = batch_names.find { |name| name.to_s.strip.downcase == record.global_comm_code_desc.to_s.downcase }
          commodities_cache[original_name] = record if original_name
        end
      else # 'level3_desc'
        # Crear mapeo case-insensitive para level3_desc
        lower_names = batch_names.map(&:to_s).map(&:strip).map(&:downcase)
        batch_results = where("LOWER(level3_desc) IN (?)", lower_names)
        
        batch_results.each do |record|
          # Buscar el nombre original que coincide (case-insensitive)
          original_name = batch_names.find { |name| name.to_s.strip.downcase == record.level3_desc.to_s.downcase }
          commodities_cache[original_name] = record if original_name
        end
      end
    end
    
    Rails.logger.info "🔍 [COMMODITY BATCH] Loaded #{commodities_cache.size} commodity references"
    commodities_cache
  end

  # OPTIMIZACIÓN: Obtener scopes para múltiples commodities en batch
  def self.scopes_for_commodities_batch(commodity_names, column_type = 'level3_desc')
    commodities_cache = find_commodities_batch(commodity_names, column_type)
    
    # Crear mapeo de commodity name -> scope
    scope_mapping = {}
    commodity_names.each do |name|
      record = commodities_cache[name]
      if record
        scope_mapping[name] = record.infinex_scope_status&.downcase == 'in scope' ? 'In scope' : 'Out of scope'
      else
        scope_mapping[name] = 'Out of scope'
      end
    end
    
    scope_mapping
  end
  
  # Scope para búsqueda global
  def self.search(query)
    return all if query.blank?
    
    where(
      "global_comm_code_desc ILIKE ? OR level1_desc ILIKE ? OR level2_desc ILIKE ? OR level3_desc ILIKE ? OR level3_desc_expanded ILIKE ? OR typical_mpn_by_manufacturer ILIKE ? OR keyword ILIKE ? OR mfr ILIKE ?",
      "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%"
    )
  end
  
  # CSV export functionality
  def self.to_csv
    require 'csv'
    attributes = %w{id global_comm_code_desc level1_desc level2_desc level3_desc infinex_scope_status autograde_scope keyword mfr level3_desc_expanded typical_mpn_by_manufacturer created_at updated_at}
    
    CSV.generate(headers: true) do |csv|
      csv << attributes.map(&:humanize)
      all.find_each do |commodity|
        csv << attributes.map { |attr| commodity.send(attr) }
      end
    end
  end
  
  # Método para forzar regeneración de embedding
  def regenerate_embedding!
    Rails.logger.info "🔄 [EMBEDDING] Force regenerating embedding for commodity reference #{id}"

    full_text = full_text_for_embedding
    if full_text.present?
      new_embedding = OpenaiService.get_embedding_for_text(full_text)
      if new_embedding
        update_columns(embedding: new_embedding, embedding_vector: new_embedding)
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

  def normalize_scope_values
    # Normalizar infinex_scope_status
    if infinex_scope_status.present?
      normalized_infinex = infinex_scope_status.to_s.strip.downcase
      self.infinex_scope_status = case normalized_infinex
                                  when 'in scope'
                                    'In Scope'
                                  when 'out of scope'
                                    'Out of Scope'
                                  else
                                    infinex_scope_status
                                  end
    end

    # Normalizar autograde_scope
    if autograde_scope.present?
      normalized_autograde = autograde_scope.to_s.strip.downcase
      self.autograde_scope = case normalized_autograde
                             when 'in scope'
                               'In Scope'
                             when 'out of scope'
                               'Out of Scope'
                             else
                               autograde_scope
                             end
    end
  end

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
          update_columns(embedding: new_embedding, embedding_vector: new_embedding)
          Rails.logger.info "✅ [EMBEDDING] Successfully regenerated embedding for commodity reference #{id}"
        else
          Rails.logger.error "❌ [EMBEDDING] Failed to generate new embedding for commodity reference #{id}"
        end
      end
    end
  end
end