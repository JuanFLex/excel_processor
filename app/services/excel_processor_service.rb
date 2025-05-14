class ExcelProcessorService
  TARGET_COLUMNS = [
    'SUGAR_ID', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 
    'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 
    'LAST_PO', 'EAU'
  ]
  
  def initialize(processed_file)
    @processed_file = processed_file
    @commodities_cache = {} # Cache para evitar consultas repetidas
  end
  
  def process_upload(file)
    begin
      # Actualizar estado
      @processed_file.update(status: 'processing')
      
      # Leer el archivo Excel
      spreadsheet = open_spreadsheet(file)
      header = spreadsheet.row(1)
      
      # Obtener una muestra de filas para identificación de columnas
      sample_rows = []
      (2..6).each do |i|
        row = Hash[[header, spreadsheet.row(i)].transpose]
        sample_rows << row if i <= spreadsheet.last_row
      end
      
      # Usar OpenAI para identificar las columnas
      column_mapping = OpenaiService.identify_columns(sample_rows, TARGET_COLUMNS)
      
      # Guardar el mapeo de columnas
      @processed_file.update(column_mapping: column_mapping)
      
      # Preparar el procesamiento por lotes
      total_rows = spreadsheet.last_row - 1 # Excluir encabezado
      batch_size = 100
      total_batches = (total_rows / batch_size.to_f).ceil
      
      # Procesar todas las filas en lotes
      (2..spreadsheet.last_row).each_slice(batch_size).with_index do |row_indices, batch_index|
        Rails.logger.info "Procesando lote #{batch_index + 1} de #{total_batches}..."
        
        # Preparar datos para procesamiento en lote
        batch_rows = []
        row_indices.each do |i|
          row_data = Hash[[header, spreadsheet.row(i)].transpose]
          batch_rows << row_data
        end
        
        # Extraer todas las descripciones para calcular embeddings en lote
        descriptions = batch_rows.map do |row|
          description_column = column_mapping['DESCRIPTION']
          description_column ? row[description_column].to_s.strip : ''
        end
        
        # Filtrar descripciones vacías
        valid_descriptions = descriptions.select(&:present?)
        description_indices = descriptions.each_with_index.select { |desc, _| desc.present? }.map { |_, idx| idx }
        
        # Obtener embeddings en lote
        description_embeddings = {}
        if valid_descriptions.any?
          embeddings = OpenaiService.get_embeddings(valid_descriptions)
          
          description_indices.each_with_index do |row_idx, embed_idx|
            description = descriptions[row_idx]
            description_embeddings[description] = embeddings[embed_idx] if embeddings[embed_idx]
          end
        end
        
        # Procesar cada fila del lote
        processed_items = []
        batch_rows.each_with_index do |row, index|
          values = extract_values(row, column_mapping)
          
          # Determinar commodity y scope si hay descripción
          if values['description'].present?
            embedding = description_embeddings[values['description']]
            
            if embedding
              # Encontrar commodity más similar (usando caché si ya se procesó)
              values['embedding'] = embedding
              
              # Buscar en caché primero
              if @commodities_cache.key?(values['description'])
                similar_commodity = @commodities_cache[values['description']]
              else
                similar_commodity = find_similar_commodity(embedding)
                # Guardar en caché
                @commodities_cache[values['description']] = similar_commodity if similar_commodity
              end
              
              if similar_commodity
                values['commodity'] = similar_commodity.level2_desc
                values['scope'] = similar_commodity.infinex_scope_status == 'In Scope' ? 'In scope' : 'Out of scope'
              else
                values['commodity'] = 'Unknown'
                values['scope'] = 'Out of scope'
              end
            else
              values['commodity'] = 'Unknown'
              values['scope'] = 'Out of scope'
            end
          end
          
          # Añadir a la lista para inserción en lote
          processed_items << values
        end
        
        # Crear los items procesados en lote
        insert_items_batch(processed_items)
      end
      
      # Generar el archivo Excel de salida
      generate_output_file
      
      # Actualizar estado
      @processed_file.update(status: 'completed', processed_at: Time.current)
      
      { success: true }
    rescue => e
      @processed_file.update(status: 'failed')
      Rails.logger.error("Error processing file: #{e.message}")
      { success: false, error: e.message }
    end
  end
  
  private
  
  def open_spreadsheet(file)
    case File.extname(file.original_filename)
    when '.csv'
      Roo::CSV.new(file.path)
    when '.xls'
      Roo::Excel.new(file.path)
    when '.xlsx'
      Roo::Excelx.new(file.path)
    else
      raise "Formato de archivo no soportado: #{file.original_filename}"
    end
  end
  
  def extract_values(row, column_mapping)
    values = {}
    
    TARGET_COLUMNS.each do |target_col|
      source_col = column_mapping[target_col]
      values[target_col.downcase] = source_col ? row[source_col] : nil
    end
    
    # Convertir tipos de datos según sea necesario
    values['std_cost'] = values['std_cost'].to_f if values['std_cost'].present?
    values['last_purchase_price'] = values['last_purchase_price'].to_f if values['last_purchase_price'].present?
    values['last_po'] = values['last_po'].to_f if values['last_po'].present?
    values['eau'] = values['eau'].to_i if values['eau'].present?
    
    values
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
          description: item_values['description'],
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
    workbook.add_worksheet(name: "Items Procesados") do |sheet|
      # Encabezados
      headers = [
        'SUGAR_ID', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 
        'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 
        'LAST_PO', 'EAU', 'Commodity', 'Scope'
      ]
      
      # Estilo para encabezados
      header_style = workbook.styles.add_style(
        bg_color: "0066CC",
        fg_color: "FFFFFF",
        b: true,
        alignment: { horizontal: :center }
      )
      
      # Añadir fila de encabezados
      sheet.add_row headers, style: header_style
      
      # Procesar items en lotes para evitar problemas de memoria
      @processed_file.processed_items.find_each(batch_size: 500) do |item|
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
          item.scope
        ]
      end
      
      # Autoajustar columnas
      sheet.auto_filter = "A1:L1"
      sheet.auto_width = true
    end
    
    # Guardar el archivo
    file_path = Rails.root.join('storage', "processed_#{@processed_file.id}_#{Time.current.to_i}.xlsx")
    package.serialize(file_path)
    
    # Guardar la ruta del archivo en el modelo
    @processed_file.update(result_file_path: file_path.to_s)
  end
end