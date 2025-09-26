class ProcessedFile < ApplicationRecord
  has_one_attached :original_file
  has_many :processed_items, dependent: :destroy
  
  validates :original_filename, presence: true
  validates :status, presence: true, inclusion: { in: ['pending', 'column_preview', 'queued', 'processing', 'completed', 'failed'] }
  
  
  VALID_STATUSES = %w[pending column_preview queued processing completed failed].freeze

  VALID_STATUSES.each do |status_name|
    define_method "#{status_name}?" do
      status == status_name
    end
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
    # FIXED: Load SQL data for accurate EAR calculations including Total Demand
    sql_caches = load_sql_caches_for_analytics

    processed_items.group_by(&:scope).transform_values do |items|
      items.sum do |item|
        total_demand = sql_caches[:total_demand][item.item.to_s.strip]
        min_price = sql_caches[:min_price][item.item.to_s.strip]
        item.ear_value(total_demand, min_price) || 0
      end
    end
  end

  def all_items_total_ear
    # Sumar EAR total de TODOS los items (incluir duplicados para EAR real)
    # FIXED: Load SQL data for accurate EAR calculations including Total Demand
    sql_caches = load_sql_caches_for_analytics

    processed_items.sum do |item|
      total_demand = sql_caches[:total_demand][item.item.to_s.strip]
      min_price = sql_caches[:min_price][item.item.to_s.strip]
      item.ear_value(total_demand, min_price) || 0
    end
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

    # FIXED: Load SQL data for accurate EAR calculations
    sql_caches = load_sql_caches_for_analytics

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

      # Meeting threshold - FIXED: Use SQL data for EAR calculation
      total_demand = sql_caches[:total_demand][item.item.to_s.strip]
      min_price = sql_caches[:min_price][item.item.to_s.strip]
      ear_value = item.ear_value(total_demand, min_price)

      if ear_value && ear_value >= ExcelProcessorConfig::EAR_THRESHOLD
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

      # FIXED: Load SQL data for accurate EAR calculations
      sql_caches = load_sql_caches_for_analytics

      # Buscar todos los items que coincidan por item number y scope
      all_matching_items = processed_items.where(item: item_numbers, scope: scope_value)
      ear = all_matching_items.sum do |item|
        total_demand = sql_caches[:total_demand][item.item.to_s.strip]
        min_price = sql_caches[:min_price][item.item.to_s.strip]
        item.ear_value(total_demand, min_price) || 0
      end
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
  
  # BULK LOAD: Consulta en chunks para evitar timeouts con archivos grandes
  def load_cross_ref_items_bulk(mfg_partnos)
    return Set.new if mfg_partnos.empty?
    return Set.new unless defined?(ItemLookup)
    
    begin
      # Filtrar nulos y crear placeholders
      valid_partnos = mfg_partnos.compact.reject(&:blank?)
      return Set.new if valid_partnos.empty?
      
      # NUEVO: Procesar en chunks para evitar timeouts con archivos grandes
      chunk_size = ExcelProcessorConfig::BATCH_SIZE # Máximo partnos por consulta
      all_results = Set.new
      total_chunks = (valid_partnos.size / chunk_size.to_f).ceil
      
      Rails.logger.info "📊 [BULK] Processing #{valid_partnos.size} partnos in #{total_chunks} chunks of #{chunk_size}"
      
      valid_partnos.each_slice(chunk_size).with_index do |partnos_chunk, index|
        Rails.logger.info "🔄 [BULK] Processing chunk #{index + 1}/#{total_chunks}"
        
        # Escapar y formatear partnos para SQL Server
        escaped_partnos = partnos_chunk.map { |pn| "'#{pn.to_s.gsub("'", "''")}'" }.join(',')
        
        # Apply component grade filter based on processed file configuration
        include_medical_auto = self.include_medical_auto_grades || false
        grade_filter = enable_medical_auto ? "AND COMPONENT_GRADE = 'AUTO'" : "AND COMPONENT_GRADE = 'COMMERCIAL'"

        # NUEVO: Agregar timeout explícito y usar execute para mayor control
        result = ItemLookup.connection.execute(
          "SET LOCK_TIMEOUT 60000; SELECT DISTINCT CROSS_REF_MPN FROM INX_dataLabCrosses
           WHERE CROSS_REF_MPN IN (#{escaped_partnos}) AND INFINEX_MPN IS NOT NULL
           #{grade_filter}"
        ).to_a
        
        chunk_results = result.flatten.to_set
        all_results.merge(chunk_results)
        
        Rails.logger.info "✅ [BULK] Chunk #{index + 1} completed: found #{chunk_results.size} matches"
      end
      
      Rails.logger.info "🎯 [BULK] Total cross-references found: #{all_results.size}"
      all_results
    rescue => e
      Rails.logger.error "Error loading cross references: #{e.message}"
      Set.new
    end
  end

  private

  # Load SQL caches for analytics calculations (charts and graphs)
  def load_sql_caches_for_analytics
    # Return mock data if using mock SQL server
    if ENV['MOCK_SQL_SERVER'] == 'true'
      return {
        total_demand: {},
        min_price: {}
      }
    end

    caches = {
      total_demand: {},
      min_price: {}
    }

    # Extract unique items from processed items
    unique_items = processed_items.pluck(:item).compact.uniq.map(&:to_s).map(&:strip)
    return caches if unique_items.empty?

    begin
      # Load Total Demand cache (only if enabled for this file)
      if enable_total_demand_lookup
        unique_items.each_slice(1000) do |batch_items|
          quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')

          result = ItemLookup.connection.select_all(
            "SELECT ITEM, TOTAL_DEMAND
             FROM ExcelProcessorAMLfind
             WHERE ITEM IN (#{quoted_items}) AND TOTAL_DEMAND IS NOT NULL"
          )

          result.rows.each do |row|
            caches[:total_demand][row[0]] = row[1]
          end
        end
      end

      # Load Min Price cache
      unique_items.each_slice(1000) do |batch_items|
        quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')

        result = ItemLookup.connection.select_all(
          "SELECT ITEM, MIN_PRICE
           FROM ExcelProcessorAMLfind
           WHERE ITEM IN (#{quoted_items}) AND MIN_PRICE IS NOT NULL"
        )

        result.rows.each do |row|
          caches[:min_price][row[0]] = row[1]
        end
      end

    rescue => e
      Rails.logger.error "Error loading SQL caches for analytics: #{e.message}"
      # Return empty caches so analytics continue without SQL data
    end

    caches
  end
end