class ProcessedFile < ApplicationRecord
  has_one_attached :original_file
  has_many :processed_items, dependent: :destroy
  
  validates :original_filename, presence: true
  validates :status, presence: true, inclusion: { in: ['pending', 'queued', 'processing', 'completed', 'failed'] }
  
  
  def completed?
    status == 'completed'
  end
  
  def failed?
    status == 'failed'
  end
  
  def pending?
    status == 'pending'
  end
  
  def processing?
    status == 'processing'
  end

  def queued?
    status == 'queued'
  end

  def analytics
    @analytics ||= calculate_analytics_optimized
  end
  
  def unique_items_count
    # Contar solo items únicos (primera aparición por item number) para métricas
    unique_items.count
  end
  
  def unique_items_by_scope
    # Agrupar solo items únicos por scope para gráficas
    unique_items.group_by(&:scope).transform_values(&:count)
  end
  
  def all_items_ear_by_scope
    # Agrupar TODOS los items por scope y sumar EAR (incluir duplicados para EAR real)
    processed_items.group_by(&:scope).transform_values do |items| 
      items.sum { |item| item.ear_value || 0 }
    end
  end
  
  def all_items_total_ear
    # Sumar EAR total de TODOS los items (incluir duplicados para EAR real)
    processed_items.sum { |item| item.ear_value || 0 }
  end
  
  def unique_items_array
    # Método público para acceder a los items únicos desde vistas
    unique_items
  end

  private
  
  def unique_items
    # Cached method to get unique items (primera aparición por item number)
    @unique_items ||= begin
      item_tracker = Set.new
      processed_items.to_a.select do |item|
        if item_tracker.include?(item.item)
          false # Skip duplicates
        else
          item_tracker.add(item.item)
          true # Keep first occurrence
        end
      end
    end
  end
  
  def calculate_analytics_optimized
    # Usar items únicos para conteos correctos, EAR se calcula después en calculate_metrics
    in_scope_items = unique_items.select { |item| item.scope == 'In scope' }
    
    # PRE-CARGAR todos los lookups de una sola vez (como hace el servicio)
    quoted_items_set = load_quoted_items_bulk(in_scope_items.map(&:item))
    cross_ref_items_set = load_cross_ref_items_bulk(in_scope_items.map(&:mfg_partno))
    
    # Categorizar items en UN SOLO LOOP
    categories = {
      in_scope_total: [],
      previously_quoted: [],
      meeting_threshold: [],
      crosses_threshold: []
    }
    
    in_scope_items.each do |item|
      # Todos van a in_scope_total
      categories[:in_scope_total] << item
      
      # Previously quoted
      if quoted_items_set.include?(item.item)
        categories[:previously_quoted] << item
      end
      
      # Meeting threshold  
      if item.ear_value && item.ear_value >= 100_000
        categories[:meeting_threshold] << item
        
        # Crosses threshold (subset de meeting_threshold)
        if cross_ref_items_set.include?(item.mfg_partno)
          categories[:crosses_threshold] << item
        end
      end
    end
    
    # Calcular métricas de cada categoría
    {
      in_scope_total: calculate_metrics(categories[:in_scope_total]),
      previously_quoted: calculate_metrics(categories[:previously_quoted]),
      meeting_threshold: calculate_metrics(categories[:meeting_threshold]),
      crosses_threshold: calculate_metrics(categories[:crosses_threshold])
    }
  end
  
  def calculate_metrics(unique_items_in_category)
    # Conteo: usar los items únicos que recibe
    count = unique_items_in_category.count
    
    # EAR: buscar TODOS los items que correspondan a estos únicos
    if unique_items_in_category.any?
      item_numbers = unique_items_in_category.map(&:item).uniq
      scope_value = unique_items_in_category.first.scope
      
      # Buscar todos los items que coincidan por item number y scope
      all_matching_items = processed_items.where(item: item_numbers, scope: scope_value)
      ear = all_matching_items.sum { |item| item.ear_value || 0 }
    else
      ear = 0
    end
    
    { ear: ear, count: count }
  end
  
  # BULK LOAD: Una sola consulta para todos los quoted items
  def load_quoted_items_bulk(item_codes)
    return Set.new if item_codes.empty?
    return Set.new unless defined?(ItemLookup)
    
    begin
      # Escapar y formatear items para SQL Server (sin parámetros ?)
      escaped_items = item_codes.map { |item| "'#{item.to_s.gsub("'", "''")}'" }.join(',')
      
      result = ItemLookup.connection.select_all(
        "SELECT DISTINCT ITEM FROM INX_rptProposalDetailNEW 
         WHERE ITEM IN (#{escaped_items})"
      )
      
      result.rows.flatten.to_set
    rescue => e
      Rails.logger.error "Error loading quoted items: #{e.message}"
      Set.new
    end
  end
  
  # BULK LOAD: Una sola consulta para todos los cross references
  def load_cross_ref_items_bulk(mfg_partnos)
    return Set.new if mfg_partnos.empty?
    return Set.new unless defined?(ItemLookup)
    
    begin
      # Filtrar nulos y crear placeholders
      valid_partnos = mfg_partnos.compact.reject(&:blank?)
      return Set.new if valid_partnos.empty?
      
      # Escapar y formatear partnos para SQL Server (sin parámetros ?)
      escaped_partnos = valid_partnos.map { |pn| "'#{pn.to_s.gsub("'", "''")}'" }.join(',')
      
      result = ItemLookup.connection.select_all(
        "SELECT DISTINCT CROSS_REF_MPN FROM INX_dataLabCrosses 
         WHERE CROSS_REF_MPN IN (#{escaped_partnos}) AND INFINEX_MPN IS NOT NULL"
      )
      
      result.rows.flatten.to_set
    rescue => e
      Rails.logger.error "Error loading cross references: #{e.message}"
      Set.new
    end
  end
end