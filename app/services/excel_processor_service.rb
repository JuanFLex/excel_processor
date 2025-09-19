class ExcelProcessorService
  
  def initialize(processed_file)
    @processed_file = processed_file
    @commodities_cache = {} # Cache para evitar consultas repetidas
    @scope_cache = {} # NUEVO: Cache para scopes de commodities existentes
    @cross_references_cache = {} # Cache para cross-references de SQL Server
    @commodity_references_cache = [] # Cache para commodity references con embeddings
    @proposal_quotes_cache = {}  # Cache para proposal quotes
    @aml_total_demand_cache = {} # Cache para Total Demand lookups
    @aml_min_price_cache = {} # Cache para Min Price lookups
    @existing_items_lookup = {} # NUEVO: Lookup table para remapping de líneas individuales
    @performance_metrics = {} # Performance timing tracker
    @process_start_time = Time.current
    @cosine_calculation_count = 0 # Counter for cosine similarity calculations
  end
  
  def process_upload(file, manual_remap = nil)
    begin
      # Actualizar estado
      @processed_file.update(status: 'processing')
      
      # Pre-cargar cross-references, commodities, proposal quotes para optimizar performance
      track_time('Cross References Cache Load') { load_cross_references_cache }
      track_time('Commodity References Cache Load') { load_commodity_references_cache }
      track_time('Proposal Quotes Cache Load') { load_proposal_quotes_cache }
      
      # NUEVO: Si es remapping, crear lookup table de items existentes antes de limpiarlos
      @existing_items_lookup = {}
      if manual_remap.present?
        Rails.logger.info "📝 [REMAP] Creating lookup table from existing items before clearing..."
        
        # Crear lookup table basado en item + descripción para poder aplicar remapping
        @processed_file.processed_items.each do |existing_item|
          # Crear múltiples claves para mayor flexibilidad en matching
          keys = [
            existing_item.item,
            existing_item.description&.strip,
            "#{existing_item.item}|#{existing_item.description&.strip}"
          ].compact
          
          keys.each do |key|
            @existing_items_lookup[key] ||= []
            @existing_items_lookup[key] << {
              id: existing_item.id,
              item: existing_item.item,
              description: existing_item.description,
              commodity: existing_item.commodity,
              scope: existing_item.scope
            }
          end
        end
        
        Rails.logger.info "🔍 [REMAP] Created lookup table with #{@existing_items_lookup.size} keys for remapping"
        
        # Ahora sí, limpiar los items existentes
        Rails.logger.info "🗑️ [REMAP] Clearing existing processed items..."
        @processed_file.processed_items.delete_all
      end
      
      # Leer el archivo Excel
      spreadsheet = open_spreadsheet(file)
      header = spreadsheet.row(1)
      total_rows = spreadsheet.last_row - 1
      
      
      # Obtener una muestra de filas para identificación de columnas
      sample_rows = []
      (2..6).each do |i|
        row = Hash[[header, spreadsheet.row(i)].transpose]
        sample_rows << row if i <= spreadsheet.last_row
      end
      
      
      # Usar OpenAI para identificar las columnas estándar (solo si no es remapeo manual)
      if manual_remap && manual_remap[:column_mapping].present?
        Rails.logger.info "🔄 [DEMO] Using manual column mapping from remap..."
        column_mapping = manual_remap[:column_mapping]
      else
        column_mapping = track_time('Column Mapping (OpenAI)') do
          OpenaiService.identify_columns(sample_rows, ExcelProcessorConfig::TARGET_COLUMNS)
        end
        
        # NUEVO: Detectar específicamente columnas de jerarquía de commodities
        level1_column = Level3DetectorService.detect_level1_column(sample_rows)
        if level1_column
          column_mapping['LEVEL1_DESC'] = level1_column
        end
        
        level2_column = Level3DetectorService.detect_level2_column(sample_rows)
        if level2_column
          column_mapping['LEVEL2_DESC'] = level2_column
        end
        
        level3_column = Level3DetectorService.detect_level3_column(sample_rows)
        if level3_column
          column_mapping['LEVEL3_DESC'] = level3_column
        end
        
        # NUEVO: Detectar específicamente si hay una columna GLOBAL_COMM_CODE_DESC exacta
        global_comm_code_column = detect_exact_global_comm_code_column(sample_rows)
        if global_comm_code_column
          column_mapping['GLOBAL_COMM_CODE_DESC'] = global_comm_code_column
        end
      end
      
      Rails.logger.info "✅ [DEMO] Columns successfully identified by AI!"
      
      # NUEVO: Detectar si el archivo tiene exactamente level3_desc o global_comm_code_desc
      has_level3_desc = column_mapping['LEVEL3_DESC'].present?
      has_global_comm_code = column_mapping['GLOBAL_COMM_CODE_DESC'].present?
      has_commodity_column = has_level3_desc || has_global_comm_code
      
      if has_commodity_column
        commodity_column = has_level3_desc ? 'LEVEL3_DESC' : 'GLOBAL_COMM_CODE_DESC'
        Rails.logger.info "💡 [DEMO] Detected exact #{commodity_column} column! Will use existing commodities and only classify scope, saving tokens."
      else
        Rails.logger.info "🔍 [DEMO] No commodity column found. Will use AI for full classification based on description."
      end
      
      # Guardar el mapeo de columnas
      @processed_file.update(column_mapping: column_mapping)
      
      
      # Preparar el procesamiento por lotes - reducir para archivos grandes
      batch_size = total_rows > 50000 ? 25 : 100
      total_batches = (total_rows / batch_size.to_f).ceil
      
      Rails.logger.info "⚡ [DEMO] Optimized processing: #{total_batches} batches of max #{batch_size} rows"
      
      # Procesar todas las filas en lotes
      (2..spreadsheet.last_row).each_slice(batch_size).with_index do |row_indices, batch_index|
        
        # Preparar datos para procesamiento en lote
        batch_rows = []
        row_indices.each do |i|
          row_data = Hash[[header, spreadsheet.row(i)].transpose]
          batch_rows << row_data
        end
        
        # Procesar cada fila del lote
        processed_items = []
        
        if has_commodity_column
          # NUEVO: Procesamiento optimizado para archivos con commodity existente
          Rails.logger.info "🎯 [DEMO] Using existing #{commodity_column} commodities, only determining scope..."
          
          processed_items = process_batch_with_commodity_desc(batch_rows, column_mapping, manual_remap)
          classified_count = processed_items.count { |item| item['commodity'] != 'Unknown' }
          
        else
          # Procesamiento original con AI para commodity
          processed_items = process_batch_with_ai_commodity(batch_rows, column_mapping, batch_index, manual_remap)
          classified_count = processed_items.count { |item| item['commodity'] != 'Unknown' }
          
        end
        
        # Cargar AML cache con los items únicos del archivo actual
        unique_items = processed_items.map { |item| item['item'] }.compact.uniq
        unique_item_mpn_pairs = processed_items.map { |item| [item['item'], item['mfg_partno']] }
          .select { |item, mpn| item.present? && mpn.present? }.uniq
        track_time('AML Cache Load (SQL Server)') { load_aml_cache_for_items(unique_items, unique_item_mpn_pairs) }
        
        # Crear los items procesados en lote
        insert_items_batch(processed_items)
      end
      
      
      # Generar el archivo Excel de salida
      track_time('Excel File Generation') { generate_output_file }
      
      
      # Actualizar estado
      @processed_file.update(status: 'completed', processed_at: Time.current)
      
      # Log performance summary
      log_performance_summary
      
      { success: true }
    rescue => e
      @processed_file.update(status: 'failed')
      Rails.logger.error("❌ [DEMO] ERROR: #{e.message}")
      { success: false, error: e.message }
    end
  end
  
  private
  
  # NUEVO: Procesar lote cuando el archivo tiene commodity desc exacto (LEVEL3_DESC o GLOBAL_COMM_CODE_DESC)
  def process_batch_with_commodity_desc(batch_rows, column_mapping, manual_remap = nil)
    processed_items = []
    cache_hits = 0
    
    batch_rows.each_with_index do |row, index|
      values = extract_values(row, column_mapping)
      
      # Obtener commodity existente del archivo (LEVEL3_DESC o GLOBAL_COMM_CODE_DESC)
      existing_commodity = nil
      commodity_column_type = nil
      if column_mapping['LEVEL3_DESC']
        existing_commodity = row[column_mapping['LEVEL3_DESC']].to_s.strip
        commodity_column_type = 'level3_desc'
      elsif column_mapping['GLOBAL_COMM_CODE_DESC']
        existing_commodity = row[column_mapping['GLOBAL_COMM_CODE_DESC']].to_s.strip
        commodity_column_type = 'global_comm_code_desc'
      end
      
      if existing_commodity.present?
        values['commodity'] = existing_commodity
        
        # Crear clave de caché que incluya el tipo de columna
        cache_key = "#{existing_commodity}|#{commodity_column_type}"
        
        # Buscar scope en caché primero
        if @scope_cache.key?(cache_key)
          values['scope'] = @scope_cache[cache_key]
          cache_hits += 1
        else
          # Buscar scope en base de datos usando commodity exacto y columna correcta
          scope = CommodityReference.scope_for_commodity(existing_commodity, commodity_column_type)
          values['scope'] = scope
          @scope_cache[cache_key] = scope
        end
        
        # Si tiene cruce en SQL Server, automáticamente In scope
        if lookup_cross_reference(values['mfg_partno']).present?
          values['scope'] = 'In scope'
        end
        
        # Aplicar remapping de líneas individuales (NUEVO)
        values = apply_line_remapping(values, manual_remap, index)
        
        # LEGACY: Aplicar cambios masivos de commodity (para retrocompatibilidad)
        if manual_remap && manual_remap[:commodity_changes]
          original_commodity = values['commodity']
          if manual_remap[:commodity_changes][original_commodity].present?
            new_commodity = manual_remap[:commodity_changes][original_commodity]
            values['commodity'] = new_commodity
            values['scope'] = CommodityReference.scope_for_commodity(new_commodity)
            
            if index % 10 == 0
            end
          end
        end
        
        # Log ocasional para mostrar procesamiento
        if index % 20 == 0
        end
      else
        values['commodity'] = 'Unknown'
        values['scope'] = 'Out of scope'
        
        # Si tiene cruce en SQL Server, automáticamente In scope aún siendo Unknown
        if lookup_cross_reference(values['mfg_partno']).present?
          values['scope'] = 'In scope'
        end
      end
      
      processed_items << values
    end
    
    if cache_hits > 0
      Rails.logger.info "⚡ [DEMO] Cache efficiency: #{cache_hits} scope lookups reused from memory"
    end
    
    processed_items
  end
  
  # NUEVO: Procesar lote con AI para commodity (método original mejorado)
  def process_batch_with_ai_commodity(batch_rows, column_mapping, batch_index, manual_remap = nil)
    # Extraer todas las descripciones para calcular embeddings en lote
    descriptions = batch_rows.map do |row|
      build_full_text_for_embedding(row, column_mapping)
    end
    
    # Filtrar descripciones vacías
    valid_descriptions = descriptions.select(&:present?)
    description_indices = descriptions.each_with_index.select { |desc, _| desc.present? }.map { |_, idx| idx }
    valid_count = valid_descriptions.size
    
    Rails.logger.info "🧠 [DEMO] Generating AI embeddings for #{valid_count} product descriptions..."
    
    # Obtener embeddings en lote
    description_embeddings = {}
    if valid_descriptions.any?
      Rails.logger.info "🚀 [DEMO] Sending #{valid_descriptions.size} descriptions to OpenAI for analysis..."
      embeddings = track_time('Embeddings Generation (OpenAI)') do
        OpenaiService.get_embeddings(valid_descriptions)
      end
      Rails.logger.info "⚡ [DEMO] Embeddings generated! Each description now has a #{embeddings.first&.size || 0}-dimensional 'fingerprint'"
      
      description_indices.each_with_index do |row_idx, embed_idx|
        full_text = descriptions[row_idx]
        description_embeddings[full_text] = embeddings[embed_idx] if embeddings[embed_idx]
      end
    end
    
    # Procesar cada fila del lote
    Rails.logger.info "🎯 [DEMO] Classifying products by comparing against catalog of #{CommodityReference.count} references (Level 3)..."
    
    processed_items = []
    classified_count = 0
    cache_hits = 0
    
    batch_rows.each_with_index do |row, index|
      values = extract_values(row, column_mapping)
      full_text = build_full_text_for_embedding(row, column_mapping)

      # Determinar commodity y scope si hay texto completo
      if full_text.present?
        # Check if context is insufficient
        if insufficient_context(full_text)
          values['commodity'] = 'Insufficient Context'
          values['scope'] = 'Requires Review'
          
          # Si tiene cruce en SQL Server, automáticamente In scope
          if lookup_cross_reference(values['mfg_partno']).present?
            values['scope'] = 'In scope'
          end
        
        else 
          embedding = description_embeddings[full_text]
          
          if embedding
            # Encontrar commodity más similar (usando caché si ya se procesó)
            values['embedding'] = embedding
            
            # Buscar en caché primero
            if @commodities_cache.key?(full_text)
              similar_commodity = @commodities_cache[full_text]
              cache_hits += 1
            else
              similar_commodity = find_similar_commodity_cached(embedding)
              # Guardar en caché
              @commodities_cache[full_text] = similar_commodity if similar_commodity
            end
            
            if similar_commodity
              values['commodity'] = similar_commodity.level3_desc  # CAMBIO: level3_desc
              values['scope'] = similar_commodity.infinex_scope_status&.downcase == 'in scope' ? 'In scope' : 'Out of scope'
              
              # Si tiene cruce en SQL Server, automáticamente In scope
              if lookup_cross_reference(values['mfg_partno']).present?
                values['scope'] = 'In scope'
              end
              
              classified_count += 1
              
              # Log ocasional para mostrar clasificaciones exitosas
              if index % 10 == 0  # Cada 10 items
              end
            else
              values['commodity'] = 'Unknown'
              values['scope'] = 'Out of scope'
            end
        
          else
            values['commodity'] = 'Unknown'
            values['scope'] = 'Out of scope'
            
            # Si tiene cruce en SQL Server, automáticamente In scope
            if lookup_cross_reference(values['mfg_partno']).present?
              values['scope'] = 'In scope'
            end
          end
        end
      else
        values['commodity'] = 'Unknown'
        values['scope'] = 'Out of scope'
        
        # Si tiene cruce en SQL Server, automáticamente In scope aún siendo Unknown
        if lookup_cross_reference(values['mfg_partno']).present?
          values['scope'] = 'In scope'
        end
      end
      
      # Aplicar remapping de líneas individuales SIEMPRE (para todos los items)
      values = apply_line_remapping(values, manual_remap, index)
      
      # LEGACY: Aplicar cambios masivos de commodity (para retrocompatibilidad)
      if manual_remap && manual_remap[:commodity_changes]
        original_commodity = values['commodity']
        if manual_remap[:commodity_changes][original_commodity].present?
          new_commodity = manual_remap[:commodity_changes][original_commodity]
          values['commodity'] = new_commodity
          values['scope'] = CommodityReference.scope_for_commodity(new_commodity)
          
          if index % 10 == 0
          end
        end
      end
      
      processed_items << values
    end
    
    if cache_hits > 0
      Rails.logger.info "⚡ [DEMO] Cache efficiency: #{cache_hits} classifications reused from memory"
    end
    
    processed_items
  end
  
  def open_spreadsheet(file)
    case File.extname(file.original_filename).downcase
    when '.csv'
      Roo::CSV.new(file.path)
    when '.xls'
      begin
        Roo::Excel.new(file.path)
      rescue => e
        Rails.logger.error "Error opening XLS file: #{e.message}"
        raise "Error reading XLS file: #{e.message}. Please ensure the file is a valid Excel .xls file. Consider converting to .xlsx format if issues persist."
      end
    when '.xlsx'
      Roo::Excelx.new(file.path)
    else
      raise "Unsupported file format: #{file.original_filename}"
    end
  end
  
  def extract_values(row, column_mapping)
    values = {}
    
    ExcelProcessorConfig::TARGET_COLUMNS.each do |target_col|
      source_col = column_mapping[target_col]
      values[target_col.downcase] = source_col ? row[source_col] : nil
    end
    
    # NUEVO: Si no hay ITEM, usar MFG_PARTNO como fallback
    if values['item'].blank? && values['mfg_partno'].present?
      values['item'] = values['mfg_partno']
      Rails.logger.info "📋 [FALLBACK] Using MFG_PARTNO as ITEM: #{values['mfg_partno']}"
    end
    
    # Convertir tipos de datos según sea necesario
    values['std_cost'] = clean_monetary_value(values['std_cost'])
    values['last_purchase_price'] = clean_monetary_value(values['last_purchase_price'])
    values['last_po'] = clean_monetary_value(values['last_po'])
    values['eau'] = values['eau'].to_i if values['eau'].present?
    
    # NUEVO: Aplicar multiplicador de volumen si está configurado
    if @processed_file.volume_multiplier.present? && @processed_file.volume_multiplier > 1 && values['eau'].present?
      original_eau = values['eau']
      values['eau'] = values['eau'] * @processed_file.volume_multiplier
      Rails.logger.info "📈 [VOLUME] EAU multiplied for item #{values['item']}: #{original_eau} × #{@processed_file.volume_multiplier} = #{values['eau']}"
    end
    
    # Estandarizar nombre de manufacturero usando cache
    values['global_mfg_name'] = @manufacturer_cache[values['global_mfg_name']] || values['global_mfg_name']
    
    values
  end
  
  # Método para limpiar y convertir valores monetarios a números
  def clean_monetary_value(value)
    return nil if value.nil?
    return value if value.is_a?(Numeric)
    
    # Si es una fecha, intentar extraer algo numérico o devolver 0
    if value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime)
      return 0.0
    end
    
    # Convertir a string para manipulación
    str_value = value.to_s.strip
    
    # Devolver 0 si está vacío después de strip
    return 0.0 if str_value.empty?
    
    # Eliminar símbolos de moneda, espacios y caracteres no numéricos
    # excepto punto decimal, coma como separador decimal y signo negativo
    cleaned = str_value.gsub(/[$€£¥\s,]/, '')  # Eliminar símbolos de moneda, espacios y comas
                      .gsub(/[^\d.-]/, '')      # Mantener solo dígitos, punto, guion
    
    # Manejar formato europeo (coma como separador decimal)
    if str_value.include?(',') && !str_value.include?('.')
      cleaned = cleaned.gsub(',', '.')
    end
    
    # Convertir a float o devolver 0 si hay error
    begin
      cleaned.to_f
    rescue
      0.0
    end
  end
  
  
  def insert_items_batch(items)
    # Insertar en lote para mejor rendimiento
    ActiveRecord::Base.transaction do
      items.each do |item_values|
        @processed_file.processed_items.create!(
          sugar_id: item_values['sugar_id'],
          item: item_values['item'],
          mfg_partno: item_values['mfg_partno'],
          global_mfg_name: item_values['global_mfg_name'],
          description: item_values['description'].presence || item_values['mfg_partno'].presence || 'No description provided',
          site: item_values['site'],
          std_cost: item_values['std_cost'],
          last_purchase_price: item_values['last_purchase_price'],
          last_po: item_values['last_po'],
          eau: item_values['eau'],
          commodity: item_values['commodity'],
          scope: item_values['scope'],
          embedding: item_values['embedding']
        )
      end
    end
  end
  
  def generate_output_file
    
    # Crear un nuevo archivo Excel
    package = Axlsx::Package.new
    workbook = package.workbook
    
    # Añadir una hoja
    workbook.add_worksheet(name: "Processed Items") do |sheet|
      # Encabezados
      headers = [
        'SFDC_QUOTE_NUMBER', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 
        'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 
        'LAST_PO', 'EAU', 'Commodity', 'Scope', 'Part Duplication Flag', 'Potential Coreworks Cross','EAR', 'EAR Threshold Status',
        'Previously Quoted', 'Quote Date', 'Previous SFDC Quote Number', 'Previously Quoted INX_MPN', 'Total Demand', 'Min Price'
      ]
      
      
      # Estilo para encabezados
      header_style = workbook.styles.add_style(
        bg_color: "FA4616",
        fg_color: "FFFFFF",
        b: true,
        alignment: { horizontal: :center },
        font_name: "Century Gothic",
        sz: 11
      )

      auxiliary_style = workbook.styles.add_style(
        bg_color: "5498c6",
        fg_color: "FFFFFF", 
        b: true,
        alignment: { horizontal: :center },
        font_name: "Century Gothic",
        sz: 11
      )
      
      # Estilos para formato de datos
      currency_style = workbook.styles.add_style(
        format_code: '$#,##0.00',
        font_name: "Century Gothic",
        sz: 11
      )
      
      thousands_style = workbook.styles.add_style(
        format_code: '#,##0',
        font_name: "Century Gothic", 
        sz: 11
      )
      
      # Estilo especial para EAR cuando usa Total Demand (fondo amarillo)
      ear_total_demand_style = workbook.styles.add_style(
        format_code: '$#,##0.00',
        font_name: "Century Gothic",
        sz: 11,
        bg_color: "FFFF99"  # Amarillo claro
      )
      
      # Definir qué columnas son del Quote form (usarán el estilo NARANJA original)
      quote_form_columns = ['ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 'LAST_PO', 'EAU', 'Commodity']

      # Crear array de estilos basado en el nombre de la columna
      header_styles = headers.map do |header|
        quote_form_columns.include?(header) ? header_style : auxiliary_style  # Quote form = NARANJA, Auxiliares = AZUL
      end

      # Agregar fila con estilos específicos por columna
      sheet.add_row headers, style: header_styles
      
      
      item_tracker = Set.new # Para rastrear items únicos

      # Procesar items - cargar todos de una vez para evitar N+1 queries
      processed_items = @processed_file.processed_items.to_a
      processed_items.each do |item|
        unique_flg = item_tracker.include?(item.item) ? 'AML' : 'Unique'
        item_tracker.add(item.item)
        lookup_data = lookup_cross_reference(item.mfg_partno) 

        proposal_data = lookup_proposal_quote(item.item, item.mfg_partno)
        total_demand_data = lookup_total_demand(item.item)
        min_price_data = lookup_min_price(item.item)
        
        # Si Previously Quoted = YES, forzar scope a "In scope"
        final_scope = proposal_data[:previously_quoted] == 'YES' ? 'In scope' : item.scope

        sheet.add_row [
          item.sugar_id,  # Mapea a SFDC_QUOTE_NUMBER
          item.item,
          item.mfg_partno,
          item.global_mfg_name,
          item.description,
          item.site,
          item.std_cost,
          item.last_purchase_price,
          item.last_po,
          item.eau,
          item.commodity,
          final_scope,
          unique_flg, 
          lookup_data&.dig(:mpn),
          item.ear_value(total_demand_data, min_price_data),  # EAR (con decimales, puede usar fallbacks)
          item.ear_threshold_status(total_demand_data, min_price_data),  # EAR Threshold Status
          proposal_data[:previously_quoted],
          proposal_data[:quote_date],
          proposal_data[:previous_sfdc_quote_number],
          proposal_data[:inx_mpn],
          total_demand_data,
          min_price_data
          
        ]
      end
      
      # Aplicar formato a columnas específicas
      # STD_COST (columna G/7), LAST_PURCHASE_PRICE (H/8), LAST_PO (I/9), EAR (O/15), Min Price (V/22) = Currency
      sheet.col_style(6, currency_style, row_offset: 1)   # STD_COST
      sheet.col_style(7, currency_style, row_offset: 1)   # LAST_PURCHASE_PRICE  
      sheet.col_style(8, currency_style, row_offset: 1)   # LAST_PO
      sheet.col_style(14, currency_style, row_offset: 1)  # EAR
      sheet.col_style(21, currency_style, row_offset: 1)  # Min Price
      
      # EAU (columna J/10), Total Demand (U/21) = Thousands
      sheet.col_style(9, thousands_style, row_offset: 1)  # EAU
      sheet.col_style(20, thousands_style, row_offset: 1) # Total Demand
      
      # Aplicar estilo especial a celdas EAR que usan fallbacks (Total Demand o Min Price)
      processed_items = @processed_file.processed_items.to_a
      processed_items.each_with_index do |item, index|
        row_num = index + 1  # +1 porque index es 0-based, pero rows también es 0-based (row 0 = header, row 1 = first data)
        total_demand_for_item = lookup_total_demand(item.item)
        min_price_for_item = lookup_min_price(item.item)
        
        if item.ear_uses_fallback?(total_demand_for_item, min_price_for_item)
          sheet.rows[row_num].cells[14].style = ear_total_demand_style  # Columna EAR (O/15)
        end
      end
      
      # Autoajustar columnas - ahora tenemos 22 columnas (A1:V1)
      sheet.auto_filter = "A1:V1"
      # Ajustar el ancho de las columnas (agregamos 1 columna más: Previously Quoted INX_MPN)
      sheet.column_widths 15, 15, 20, 20, 30, 15, 15, 15, 15, 15, 15, 15, 20, 25, 15, 25, 15, 18, 20, 18, 15, 15
    end
    
    # Guardar el archivo
    file_path = Rails.root.join('storage', "processed_#{@processed_file.id}_#{Time.current.to_i}.xlsx")
    package.serialize(file_path)
    
    
    # Guardar la ruta del archivo en el modelo
    @processed_file.update(result_file_path: file_path.to_s)
  end

  # Método para construir texto completo para embedding con formato estructurado (matching con CommodityReference)
  def build_full_text_for_embedding(row, column_mapping)
    embedding_parts = []
    
    # Item/Part como Commodity principal
    item = row[column_mapping['ITEM']]&.to_s&.strip
    mfg_partno = row[column_mapping['MFG_PARTNO']]&.to_s&.strip
    commodity_name = item.present? ? item : mfg_partno
    
    if commodity_name.present?
      # Limpiar y normalizar nombre del commodity
      clean_name = commodity_name.gsub(/[^A-Za-z0-9\s,\-]/, '').gsub(/\s+/, '_').upcase
      embedding_parts << "Product: #{clean_name}"
    end
    
    # Descripción detallada (expandida para mejor matching)
    if column_mapping['DESCRIPTION']
      description = row[column_mapping['DESCRIPTION']].to_s.strip
      if description.present?
        expanded_description = DescriptionExpanderService.expand(description)
        embedding_parts << "Description: #{expanded_description}"
      end
    end
    
    # Fabricante
    if column_mapping['GLOBAL_MFG_NAME']
      manufacturer = row[column_mapping['GLOBAL_MFG_NAME']].to_s.strip
      if manufacturer.present?
        embedding_parts << "Manufacturer: #{manufacturer}"
      end
    end
    
    # MPN siempre debe aparecer para matching con typical_mpn_by_manufacturer
    if mfg_partno.present?
      embedding_parts << "MPN: #{mfg_partno}"
    end
    
    # Campos de commodity existentes si están disponibles
    additional_fields = ['GLOBAL_COMM_CODE_DESC', 'LEVEL1_DESC', 'LEVEL2_DESC', 'LEVEL3_DESC']
    category_parts = []
    
    additional_fields.each do |field|
      if column_mapping[field]
        field_value = row[column_mapping[field]].to_s.strip
        if field_value.present?
          case field
          when 'GLOBAL_COMM_CODE_DESC'
            embedding_parts << "Global Code: #{field_value}"
          when 'LEVEL1_DESC', 'LEVEL2_DESC', 'LEVEL3_DESC'
            category_parts << field_value
          end
        end
      end
    end
    
    # Agregar jerarquía de categorías si tenemos datos (incluso si solo es LEVEL1 o LEVEL2)
    if category_parts.any?
      embedding_parts << "Category Hierarchy: #{category_parts.join(' > ')}"
    end
    
    # Información técnica removida - no aporta valor para similitud
    # technical_info = []
    # if row[column_mapping['SITE']]&.to_s&.strip&.present?
    #   technical_info << "Site: #{row[column_mapping['SITE']].to_s.strip}"
    # end
    # 
    # if technical_info.any?
    #   embedding_parts << "Technical Info: #{technical_info.join(', ')}"
    # end
    
    embedding_parts.join("\n")
  end

  def insufficient_context(text)
    return true if text.length < 10
    return true if text.split(/[,;\s\-_|\/]+/).count { |word| word.length >= 3 } < 2
    false
  end
  
  # Pre-cargar todos los cross-references para optimizar performance
  def load_cross_references_cache
    Rails.logger.info "⚡ [PERFORMANCE] Loading cross-references and manufacturer mappings cache..."
    start_time = Time.current
    
    # Pre-cargar manufacturer mappings
    @manufacturer_cache = ManufacturerMapping.pluck(:original_name, :standardized_name).to_h
    
    if ENV['MOCK_SQL_SERVER'] == 'true'
      # Usar datos del mock
      MockItemLookup.send(:mock_crosses).each do |mpn, data|
        @cross_references_cache[mpn] = data
      end
      cache_size = @cross_references_cache.size
    else
      # Cargar datos reales de SQL Server en una sola consulta
      begin
        result = ItemLookup.connection.select_all(
          "SELECT DISTINCT CROSS_REF_MPN, SUPPLIER_PN, INFINEX_MPN, INFINEX_COST, CROSS_REF_MFG 
           FROM INX_dataLabCrosses 
           WHERE CROSS_REF_MPN IS NOT NULL"
        )
        
        result.rows.each do |row|
          @cross_references_cache[row[0]] = {
            supplier_pn: row[1],
            mpn: row[2],
            cw_cost: row[3],
            manufacturer: row[4]
          }
        end
        cache_size = @cross_references_cache.size
      rescue => e
        Rails.logger.error "Error loading cross-references cache: #{e.message}"
        cache_size = 0
      end
    end
    
    load_time = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    mfg_cache_size = @manufacturer_cache.size
    Rails.logger.info "⚡ [PERFORMANCE] Caches loaded: #{cache_size} cross-refs + #{mfg_cache_size} manufacturers in #{load_time}ms"
  end
  
  # Método optimizado para lookup usando cache
  def lookup_cross_reference(mfg_partno)
    return nil if mfg_partno.blank?
    @cross_references_cache[mfg_partno]
  end
  
  # Pre-cargar commodity references para optimizar búsqueda de similitud
  def load_commodity_references_cache
    Rails.logger.info "⚡ [PERFORMANCE] Loading commodity references cache..."
    start_time = Time.current
    
    # Cargar todos los commodities con embeddings
    @commodity_references_cache = CommodityReference.where.not(embedding: nil).to_a
    
    cache_size = @commodity_references_cache.size
    memory_mb = (cache_size * ExcelProcessorConfig::MEMORY_ESTIMATION_FACTOR / ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(1) # Estimación de memoria en MB
    load_time = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    
    Rails.logger.info "⚡ [PERFORMANCE] Commodity cache loaded: #{cache_size} entries (~#{memory_mb} MB) in #{load_time}ms"
  end
  
  # Método optimizado para encontrar commodity similar usando cache
  def find_similar_commodity_cached(embedding)
    return nil if embedding.nil? || @commodity_references_cache.empty?
    
    best_match = nil
    best_similarity = -Float::INFINITY
    
    start_time = Time.current
    batch_cosine_calculations = 0
    
    @commodity_references_cache.each do |commodity|
      next unless commodity.embedding.is_a?(Array)
      
      # Calcular similitud de coseno (mismo algoritmo que antes)
      dot_product = 0
      commodity.embedding.each_with_index do |val, i|
        dot_product += val * embedding[i]
      end
      
      batch_cosine_calculations += 1
      @cosine_calculation_count += 1
      
      if dot_product > best_similarity
        best_similarity = dot_product
        best_match = commodity
      end
    end
    
    elapsed_ms = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    Rails.logger.info "⏱️ [TIMING] Cosine similarity calculations: #{batch_cosine_calculations} calculations in #{elapsed_ms}ms" if elapsed_ms > 1
    
    best_match
    end

    def load_proposal_quotes_cache
    Rails.logger.info "⚡ [PERFORMANCE] Loading proposal quotes cache..."
    start_time = Time.current
    
    if ENV['MOCK_SQL_SERVER'] == 'true'
      # Mock data para testing
      @proposal_quotes_cache = {}
      cache_size = 0
    else
      # Conexión real a SQL Server
      begin
        # Consulta optimizada: obtener el registro más reciente por ITEM
        result = ItemLookup.connection.select_all(
          "SELECT ITEM, LOG_DATE, SUGAR_ID, INX_MPN
          FROM (
            SELECT ITEM, LOG_DATE, SUGAR_ID, INX_MPN,
                    ROW_NUMBER() OVER (PARTITION BY ITEM ORDER BY LOG_DATE DESC) as rn
            FROM INX_rptProposalDetailNEW
            WHERE ITEM IS NOT NULL
          ) ranked
          WHERE rn = 1"
        )
        
        result.rows.each do |row|
          item = row[0]
          log_date = row[1]
          sugar_id = row[2]
          inx_mpn = row[3]
          
          @proposal_quotes_cache[item] = {
            previously_quoted: 'YES',
            quote_date: log_date,
            previous_sfdc_quote_number: sugar_id,
            inx_mpn: inx_mpn
          }
        end
        
        cache_size = @proposal_quotes_cache.size
      rescue => e
        Rails.logger.error "Error loading proposal quotes cache: #{e.message}"
        cache_size = 0
      end
    end
    
    load_time = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    Rails.logger.info "⚡ [PERFORMANCE] Proposal quotes cache loaded: #{cache_size} entries in #{load_time}ms"
  end

  def lookup_proposal_quote(item, mfg_partno = nil)
    return nil if item.blank?
    
    # Si el item es igual al mfg_partno, significa que estamos usando fallback MPN
    # En este caso, no buscar y devolver "NO" directamente
    if mfg_partno.present? && item == mfg_partno
      Rails.logger.debug "🚫 [PROPOSAL] Skipping lookup for MPN fallback: #{item}"
      return {
        previously_quoted: 'NO',
        quote_date: nil,
        previous_sfdc_quote_number: nil
      }
    end
    
    # Si existe en cache, devolver datos
    if @proposal_quotes_cache.key?(item)
      @proposal_quotes_cache[item]
    else
      # Si no existe, devolver estructura con "NO"
      {
        previously_quoted: 'NO',
        quote_date: nil,
        previous_sfdc_quote_number: nil,
        inx_mpn: nil
      }
    end
  end

  def load_aml_cache_for_items(unique_items, unique_item_mpn_pairs = [])
    Rails.logger.info "⚡ [PERFORMANCE] Loading AML cache for #{unique_items.size} unique items..."
    start_time = Time.current
    
    @aml_total_demand_cache = {}
    @aml_min_price_cache = {}
    
    if ENV['MOCK_SQL_SERVER'] == 'true'
      # Mock data para testing usando MockItemLookup
      Rails.logger.info "🎭 [MOCK SQL] Loading mock AML data..."
      
      mock_data = MockItemLookup.mock_aml_data
      @aml_total_demand_cache = @processed_file.enable_total_demand_lookup ? mock_data[:total_demand] : {}
      @aml_min_price_cache = mock_data[:min_price]
      cache_size = @aml_total_demand_cache.size + @aml_min_price_cache.size
    else
      # Conexión real a SQL Server - procesar en batches de 1000
      begin
        total_demand_count = 0
        min_price_count = 0
        
        # Procesar Total Demand en batches solo si está habilitado
        if @processed_file.enable_total_demand_lookup
          unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE).with_index do |batch_items, batch_index|
            Rails.logger.info "  📦 [BATCH] Processing Total Demand batch #{batch_index + 1} (#{batch_items.size} items)..."
            
            quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')
            
            result = ItemLookup.connection.select_all(
              "SELECT ITEM, TOTAL_DEMAND
               FROM ExcelProcessorAMLfind
               WHERE ITEM IN (#{quoted_items}) AND TOTAL_DEMAND IS NOT NULL"
            )
            
            result.rows.each do |row|
              item = row[0]
              total_demand = row[1]
              @aml_total_demand_cache[item] = total_demand
              total_demand_count += 1
            end
          end
        else
          Rails.logger.info "⏭️ [SKIP] Total Demand lookup disabled for this file"
        end
        
        # Procesar Min Price en batches (ahora solo usa items, no mpn)
        unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE).with_index do |batch_items, batch_index|
          Rails.logger.info "  📦 [BATCH] Processing Min Price batch #{batch_index + 1} (#{batch_items.size} items)..."
          
          quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')
          
          result = ItemLookup.connection.select_all(
            "SELECT ITEM, MIN_PRICE
             FROM ExcelProcessorAMLfind
             WHERE ITEM IN (#{quoted_items}) AND MIN_PRICE IS NOT NULL"
          )
          
          result.rows.each do |row|
            item = row[0]
            min_price = row[1]
            @aml_min_price_cache[item] = min_price
            min_price_count += 1
          end
        end
        
        cache_size = total_demand_count + min_price_count
      rescue => e
        Rails.logger.error "Error loading AML cache: #{e.message}"
        cache_size = 0
      end
    end
    
    load_time = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    Rails.logger.info "⚡ [PERFORMANCE] AML cache loaded: #{@aml_total_demand_cache.size} Total Demand + #{@aml_min_price_cache.size} Min Price entries in #{load_time}ms"
    
  end

  def lookup_total_demand(item)
    return nil if item.blank?
    
    # Check if Total Demand lookup is enabled for this file
    return nil unless @processed_file.enable_total_demand_lookup
    
    # USE CACHE - lookup from pre-loaded batch cache for performance
    return @aml_total_demand_cache[item.strip]
  end

  def lookup_min_price(item)
    return nil if item.blank?
    @aml_min_price_cache[item.strip]
  end
  
  # NUEVO: Aplicar remapping de líneas individuales usando lookup table
  def apply_line_remapping(values, manual_remap, current_index)
    return values unless manual_remap && manual_remap[:line_remapping] && @existing_items_lookup
    
    # DEBUG: Log lo que tenemos
    
    # Estrategia: Buscar por item + descripción usando lookup table
    item_identifier = values['item'] || values['mfg_partno'] || values['description']
    
    # Claves de búsqueda en el lookup table
    search_keys = [
      values['item'],
      values['description']&.strip,
      "#{values['item']}|#{values['description']&.strip}"
    ].compact
    
    
    # Buscar en lookup table
    matching_items = []
    search_keys.each do |key|
      if @existing_items_lookup[key]
        matching_items.concat(@existing_items_lookup[key])
      end
    end
    
    matching_items.uniq! { |item| item[:id] }
    
    matching_items.each do |existing_item|
      remap_key = "#{existing_item[:id]}_commodity"
      
      if manual_remap[:line_remapping][remap_key].present?
        new_commodity = manual_remap[:line_remapping][remap_key]
        original_commodity = values['commodity']
        
        # Aplicar el remapping
        values['commodity'] = new_commodity
        values['scope'] = CommodityReference.scope_for_commodity(new_commodity)
        
        break # Solo aplicar el primer match
      end
    end
    
    values
  end
  
  # Performance timing helper
  def track_time(operation_name)
    start_time = Time.current
    result = yield
    elapsed_ms = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    @performance_metrics[operation_name] = elapsed_ms
    Rails.logger.info "⏱️ [TIMING] #{operation_name}: #{elapsed_ms}ms"
    result
  end

  # Log final performance summary
  def log_performance_summary
    total_time = ((Time.current - @process_start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    
    Rails.logger.info "📊 [PERFORMANCE SUMMARY] Processing completed in #{total_time}ms"
    Rails.logger.info "📊 [COSINE SIMILARITY] Total cosine similarity calculations: #{@cosine_calculation_count}"
    
    @performance_metrics.each do |operation, time_ms|
      percentage = ((time_ms / total_time) * 100).round(1)
      Rails.logger.info "📊   #{operation}: #{time_ms}ms (#{percentage}%)"
    end
    
    # Identify bottlenecks
    if @performance_metrics.any?
      slowest = @performance_metrics.max_by { |_, time| time }
      Rails.logger.info "🐌 [BOTTLENECK] Slowest operation: #{slowest[0]} (#{slowest[1]}ms)"
    end
    
    # Additional tracking for cosine similarity operations
    Rails.logger.info "🔍 [COSINE SIMILARITY] Detailed timing information has been logged throughout the process"
  end

  # Detectar columna GLOBAL_COMM_CODE_DESC con nombre exacto
  def detect_exact_global_comm_code_column(sample_rows)
    return nil if sample_rows.empty?
    
    headers = sample_rows.first.keys
    
    # Buscar exactamente estos nombres de columna
    exact_matches = headers.select do |header|
      header_normalized = header.to_s.strip
      header_normalized == 'GLOBAL_COMM_CODE_DESC' || header_normalized == 'GLOBAL COMM CODE DESC'
    end
    
    if exact_matches.any?
      Rails.logger.info "🎯 [GLOBAL_COMM_CODE] Detected exact column: #{exact_matches.first}"
      return exact_matches.first
    end
    
    nil
  end
end