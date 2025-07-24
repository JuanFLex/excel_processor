class ExcelProcessorService
  TARGET_COLUMNS = [
    'SUGAR_ID', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 
    'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 
    'LAST_PO', 'EAU'
  ]
  
  def initialize(processed_file)
    @processed_file = processed_file
    @commodities_cache = {} # Cache para evitar consultas repetidas
    @scope_cache = {} # NUEVO: Cache para scopes de commodities existentes
    @cross_references_cache = {} # Cache para cross-references de SQL Server
  end
  
  def process_upload(file, manual_remap = nil)
    begin
      # Actualizar estado
      @processed_file.update(status: 'processing')
      Rails.logger.info "🚀 [DEMO] Starting file processing: #{@processed_file.original_filename}"
      
      # Pre-cargar cross-references para optimizar performance
      load_cross_references_cache
      
      # Leer el archivo Excel
      Rails.logger.info "📖 [DEMO] Reading Excel file and analyzing structure..."
      spreadsheet = open_spreadsheet(file)
      header = spreadsheet.row(1)
      total_rows = spreadsheet.last_row - 1
      
      Rails.logger.info "📊 [DEMO] File processed: #{total_rows} data rows detected"
      Rails.logger.info "📋 [DEMO] Columns found: #{header.join(', ')}"
      
      # Obtener una muestra de filas para identificación de columnas
      Rails.logger.info "🤖 [DEMO] Sending data sample to OpenAI for column identification..."
      sample_rows = []
      (2..6).each do |i|
        row = Hash[[header, spreadsheet.row(i)].transpose]
        sample_rows << row if i <= spreadsheet.last_row
      end
      
      Rails.logger.info "🔍 [DEMO] OpenAI is analyzing #{sample_rows.size} sample rows..."
      
      # Usar OpenAI para identificar las columnas estándar (solo si no es remapeo manual)
      if manual_remap && manual_remap[:column_mapping].present?
        Rails.logger.info "🔄 [DEMO] Using manual column mapping from remap..."
        column_mapping = manual_remap[:column_mapping]
      else
        column_mapping = OpenaiService.identify_columns(sample_rows, TARGET_COLUMNS)
        
        # NUEVO: Detectar específicamente si hay una columna level3_desc
        level3_column = Level3DetectorService.detect_level3_column(sample_rows)
        if level3_column
          column_mapping['LEVEL3_DESC'] = level3_column
        end
      end
      
      Rails.logger.info "✅ [DEMO] Columns successfully identified by AI!"
      column_mapping.each do |target, source|
        if source
          Rails.logger.info "   🎯 [DEMO] #{target} ← #{source}"
        else
          Rails.logger.info "   ❌ [DEMO] #{target} ← (not found)"
        end
      end
      
      # NUEVO: Detectar si el archivo tiene exactamente level3_desc
      has_level3_desc = column_mapping['LEVEL3_DESC'].present?
      
      if has_level3_desc
        Rails.logger.info "💡 [DEMO] Detected exact LEVEL3_DESC column! Will use existing commodities and only classify scope, saving tokens."
      else
        Rails.logger.info "🔍 [DEMO] No LEVEL3_DESC column found. Will use AI for full classification based on description."
      end
      
      # Guardar el mapeo de columnas
      @processed_file.update(column_mapping: column_mapping)
      
      Rails.logger.info "💾 [DEMO] Preparing to process #{total_rows} rows with #{has_level3_desc ? 'level3-direct' : 'full'} AI analysis..."
      
      # Preparar el procesamiento por lotes
      batch_size = 100
      total_batches = (total_rows / batch_size.to_f).ceil
      
      Rails.logger.info "⚡ [DEMO] Optimized processing: #{total_batches} batches of max #{batch_size} rows"
      
      # Procesar todas las filas en lotes
      (2..spreadsheet.last_row).each_slice(batch_size).with_index do |row_indices, batch_index|
        Rails.logger.info "🔄 [DEMO] Processing batch #{batch_index + 1} of #{total_batches}..."
        
        # Preparar datos para procesamiento en lote
        batch_rows = []
        row_indices.each do |i|
          row_data = Hash[[header, spreadsheet.row(i)].transpose]
          batch_rows << row_data
        end
        
        # Procesar cada fila del lote
        processed_items = []
        
        if has_level3_desc
          # NUEVO: Procesamiento optimizado para archivos con level3_desc existente
          Rails.logger.info "🎯 [DEMO] Using existing level3_desc commodities, only determining scope..."
          
          processed_items = process_batch_with_level3_desc(batch_rows, column_mapping, manual_remap)
          classified_count = processed_items.count { |item| item['commodity'] != 'Unknown' }
          
          Rails.logger.info "📊 [DEMO] Batch completed: #{classified_count} of #{batch_rows.size} products processed with existing level3_desc commodities"
        else
          # Procesamiento original con AI para commodity
          processed_items = process_batch_with_ai_commodity(batch_rows, column_mapping, batch_index, manual_remap)
          classified_count = processed_items.count { |item| item['commodity'] != 'Unknown' }
          
          Rails.logger.info "📊 [DEMO] Batch completed: #{classified_count} of #{batch_rows.size} products successfully classified by AI"
        end
        
        # Crear los items procesados en lote
        Rails.logger.info "💾 [DEMO] Saving #{processed_items.size} processed products to database..."
        insert_items_batch(processed_items)
      end
      
      Rails.logger.info "🎨 [DEMO] Generating standardized Excel file with all classifications..."
      
      # Generar el archivo Excel de salida
      generate_output_file
      
      Rails.logger.info "🎉 [DEMO] Processing completed successfully!"
      Rails.logger.info "📈 [DEMO] Final statistics:"
      Rails.logger.info "   📊 Total products processed: #{@processed_file.processed_items.count}"
      Rails.logger.info "   🎯 Products classified: #{@processed_file.processed_items.where.not(commodity: 'Unknown').count}"
      Rails.logger.info "   ✅ In scope: #{@processed_file.processed_items.where(scope: 'In scope').count}"
      Rails.logger.info "   ❌ Out of scope: #{@processed_file.processed_items.where(scope: 'Out of scope').count}"
      
      # Actualizar estado
      @processed_file.update(status: 'completed', processed_at: Time.current)
      
      { success: true }
    rescue => e
      @processed_file.update(status: 'failed')
      Rails.logger.error("❌ [DEMO] ERROR: #{e.message}")
      { success: false, error: e.message }
    end
  end
  
  private
  
  # NUEVO: Procesar lote cuando el archivo tiene level3_desc exacto
  def process_batch_with_level3_desc(batch_rows, column_mapping, manual_remap = nil)
    processed_items = []
    cache_hits = 0
    
    batch_rows.each_with_index do |row, index|
      values = extract_values(row, column_mapping)
      
      # Obtener level3_desc existente del archivo
      existing_level3_desc = nil
      if column_mapping['LEVEL3_DESC']
        existing_level3_desc = row[column_mapping['LEVEL3_DESC']].to_s.strip
      end
      
      if existing_level3_desc.present?
        values['commodity'] = existing_level3_desc
        
        # Buscar scope en caché primero
        if @scope_cache.key?(existing_level3_desc)
          values['scope'] = @scope_cache[existing_level3_desc]
          cache_hits += 1
        else
          # Buscar scope en base de datos usando level3_desc exacto
          scope = CommodityReference.scope_for_commodity(existing_level3_desc)
          values['scope'] = scope
          @scope_cache[existing_level3_desc] = scope
        end
        
        # Si tiene cruce en SQL Server, automáticamente In scope
        if lookup_cross_reference(values['mfg_partno']).present?
          values['scope'] = 'In scope'
        end
        
        # SIMPLE: Aplicar cambios de commodity si existen
        if manual_remap && manual_remap[:commodity_changes]
          original_commodity = values['commodity']
          if manual_remap[:commodity_changes][original_commodity].present?
            new_commodity = manual_remap[:commodity_changes][original_commodity]
            values['commodity'] = new_commodity
            values['scope'] = CommodityReference.scope_for_commodity(new_commodity)
            
            if index % 10 == 0
              Rails.logger.info "   🔄 [REMAP] '#{original_commodity}' → '#{new_commodity}'"
            end
          end
        end
        
        # Log ocasional para mostrar procesamiento
        if index % 20 == 0
          Rails.logger.info "   ✨ [DEMO] '#{existing_level3_desc}' → Scope: #{values['scope']}"
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
      embeddings = OpenaiService.get_embeddings(valid_descriptions)
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
        
        # Log ocasional para mostrar deteccion
          if index % 10 == 0
            Rails.logger.info " [DEMO] '#{full_text}...' → Insufficient context"
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
              similar_commodity = find_similar_commodity(embedding)
              # Guardar en caché
              @commodities_cache[full_text] = similar_commodity if similar_commodity
            end
            
            if similar_commodity
              values['commodity'] = similar_commodity.level3_desc  # CAMBIO: level3_desc
              values['scope'] = similar_commodity.infinex_scope_status == 'In Scope' ? 'In scope' : 'Out of scope'
              
              # Si tiene cruce en SQL Server, automáticamente In scope
              if lookup_cross_reference(values['mfg_partno']).present?
                values['scope'] = 'In scope'
              end
              
              classified_count += 1
              
              # SIMPLE: Aplicar cambios de commodity si existen  
              if manual_remap && manual_remap[:commodity_changes]
                original_commodity = values['commodity']
                if manual_remap[:commodity_changes][original_commodity].present?
                  new_commodity = manual_remap[:commodity_changes][original_commodity]
                  values['commodity'] = new_commodity
                  values['scope'] = CommodityReference.scope_for_commodity(new_commodity)
                  
                  if index % 10 == 0
                    Rails.logger.info "   🔄 [REMAP] '#{original_commodity}' → '#{new_commodity}'"
                  end
                end
              end
              
              # Log ocasional para mostrar clasificaciones exitosas
              if index % 10 == 0  # Cada 10 items
                Rails.logger.info "   ✨ [DEMO] '#{full_text[0..50]}...' → Classified as: #{values['commodity']}"
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
      end
      
      processed_items << values
    end
    
    if cache_hits > 0
      Rails.logger.info "⚡ [DEMO] Cache efficiency: #{cache_hits} classifications reused from memory"
    end
    
    processed_items
  end
  
  def open_spreadsheet(file)
    case File.extname(file.original_filename)
    when '.csv'
      Roo::CSV.new(file.path)
    when '.xls'
      Roo::Excel.new(file.path)
    when '.xlsx'
      Roo::Excelx.new(file.path)
    else
      raise "Unsupported file format: #{file.original_filename}"
    end
  end
  
  def extract_values(row, column_mapping)
    values = {}
    
    TARGET_COLUMNS.each do |target_col|
      source_col = column_mapping[target_col]
      values[target_col.downcase] = source_col ? row[source_col] : nil
    end
    
    # Convertir tipos de datos según sea necesario
    values['std_cost'] = clean_monetary_value(values['std_cost'])
    values['last_purchase_price'] = clean_monetary_value(values['last_purchase_price'])
    values['last_po'] = clean_monetary_value(values['last_po'])
    values['eau'] = values['eau'].to_i if values['eau'].present?
    
    # Estandarizar nombre de manufacturero
    values['global_mfg_name'] = ManufacturerMapping.standardize(values['global_mfg_name'])
    
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
  
  def find_similar_commodity(embedding)
    CommodityReference.find_most_similar(embedding).first
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
    Rails.logger.info "📝 [DEMO] Creating Excel workbook with standardized format..."
    
    # Crear un nuevo archivo Excel
    package = Axlsx::Package.new
    workbook = package.workbook
    
    # Añadir una hoja
    workbook.add_worksheet(name: "Processed Items") do |sheet|
      # Encabezados
      headers = [
        'SUGAR_ID', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 
        'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 
        'LAST_PO', 'EAU', 'Commodity', 'Scope', 'Unique_flg', 'POTENTIAL_CW_MPN'
      ]
      
      Rails.logger.info "📋 [DEMO] Adding #{headers.size} standardized columns to Excel file..."
      
      # Estilo para encabezados
      header_style = workbook.styles.add_style(
        bg_color: "FA4616",
        fg_color: "FFFFFF",
        b: true,
        alignment: { horizontal: :center },
        font_name: "Century Gothic",
        sz: 11
      )
      
      # Añadir fila de encabezados
      sheet.add_row headers, style: header_style
      
      Rails.logger.info "💾 [DEMO] Writing #{@processed_file.processed_items.count} classified products to Excel..."
      
      item_tracker = Set.new # Para rastrear items únicos

      # Procesar items en lotes para evitar problemas de memoria
      @processed_file.processed_items.find_each(batch_size: 500) do |item|
        unique_flg = item_tracker.include?(item.item) ? 'AML' : 'Unique'
        item_tracker.add(item.item)
        lookup_data = lookup_cross_reference(item.mfg_partno) 

        sheet.add_row [
          item.sugar_id,
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
          item.scope,
          unique_flg, 
          lookup_data&.dig(:mpn)
        ]
      end
      
      # Autoajustar columnas
      sheet.auto_filter = "A1:N1"
      # Ajustar el ancho de las columnas
      sheet.column_widths 15, 15, 20, 20, 30, 15, 15, 15, 15, 15, 15, 15, 20, 15
    end
    
    # Guardar el archivo
    file_path = Rails.root.join('storage', "processed_#{@processed_file.id}_#{Time.current.to_i}.xlsx")
    package.serialize(file_path)
    
    Rails.logger.info "✅ [DEMO] Excel file successfully generated: #{File.basename(file_path)}"
    Rails.logger.info "📁 [DEMO] File size: #{(File.size(file_path) / 1024.0).round(2)} KB"
    
    # Guardar la ruta del archivo en el modelo
    @processed_file.update(result_file_path: file_path.to_s)
  end

  #Metodo para construir texto completo para embedding incluyendo campos adicionales.
  def build_full_text_for_embedding(row, column_mapping)
    text_parts=[]

    #Descripcion (campo principal)
    if column_mapping['DESCRIPTION']
      description = row[column_mapping['DESCRIPTION']].to_s.strip
      text_parts << description if description.present?
    end

    #Campos adicionales para concatenar
    additional_fields = ['GLOBAL_COMM_CODE_DESC','LEVEL1_DESC','LEVEL2_DESC','LEVEL3_DESC']
    additional_fields.each do |field|
      if column_mapping[field]
        field_value = row[column_mapping[field]].to_s.strip
        text_parts << field_value if field_value.present?
      end
    end
    text_parts.join(' ')
  end

  def insufficient_context(text)
    return true if text.length < 10
    return true if text.split(/[,;\s\-_|\/]+/).count { |word| word.length >= 3 } < 2
    false
  end
  
  # Pre-cargar todos los cross-references para optimizar performance
  def load_cross_references_cache
    Rails.logger.info "⚡ [PERFORMANCE] Loading cross-references cache from SQL Server..."
    start_time = Time.current
    
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
    
    load_time = ((Time.current - start_time) * 1000).round(2)
    Rails.logger.info "⚡ [PERFORMANCE] Cross-references cache loaded: #{cache_size} entries in #{load_time}ms"
  end
  
  # Método optimizado para lookup usando cache
  def lookup_cross_reference(mfg_partno)
    return nil if mfg_partno.blank?
    @cross_references_cache[mfg_partno]
  end
end