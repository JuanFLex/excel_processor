class ExcelProcessorService
  TARGET_COLUMNS = [
    'SUGAR_ID', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 
    'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 
    'LAST_PO', 'EAU'
  ]
  
  def initialize(processed_file)
    @processed_file = processed_file
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
      
      # Procesar todas las filas
      (2..spreadsheet.last_row).each do |i|
        row = Hash[[header, spreadsheet.row(i)].transpose]
        process_row(row, column_mapping)
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
  
  def process_row(row, column_mapping)
    # Extraer valores según el mapeo
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
    
    # Si hay descripción, obtener el embedding y determinar commodity y scope
    if values['description'].present?
      # Obtener embedding para la descripción
      description_embedding = OpenaiService.get_embedding_for_text(values['description'])
      
      # Encontrar commodity más similar
      similar_commodity = CommodityReference.find_most_similar(description_embedding).first
      
      if similar_commodity
        values['commodity'] = similar_commodity.level2_desc
        values['scope'] = similar_commodity.infinex_scope_status == 'In Scope' ? 'In scope' : 'Out of scope'
      else
        values['commodity'] = 'Unknown'
        values['scope'] = 'Out of scope'
      end
      
      # Guardar el embedding
      values['embedding'] = description_embedding
    end
    
    # Crear el item procesado
    @processed_file.processed_items.create!(
      sugar_id: values['sugar_id'],
      item: values['item'],
      mfg_partno: values['mfg_partno'],
      global_mfg_name: values['global_mfg_name'],
      description: values['description'],
      site: values['site'],
      std_cost: values['std_cost'],
      last_purchase_price: values['last_purchase_price'],
      last_po: values['last_po'],
      eau: values['eau'],
      commodity: values['commodity'],
      scope: values['scope'],
      embedding: values['embedding']
    )
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
      
      # Añadir datos
      @processed_file.processed_items.find_each do |item|
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