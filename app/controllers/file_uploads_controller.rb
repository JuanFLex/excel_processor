class FileUploadsController < ApplicationController
  def index
    @processed_files = ProcessedFile.order(created_at: :desc).page(params[:page]).per(10)
  end
  
  def new
    @processed_file = ProcessedFile.new
  end
  
  def create
    @processed_file = ProcessedFile.new(original_filename: file_params[:file].original_filename, status: 'pending')
    
    if @processed_file.save
      # ACTUALIZADO: Guardar archivo original en Active Storage
      uploaded_file = file_params[:file]
      @processed_file.original_file.attach(uploaded_file)
      
      # Guardar el archivo en una ubicación temporal para procesamiento
      temp_path = Rails.root.join('tmp', "upload_#{@processed_file.id}_#{Time.current.to_i}#{File.extname(uploaded_file.original_filename)}")
      
      # CORREGIDO: Rewind el archivo antes de leer
      uploaded_file.rewind
      File.open(temp_path, 'wb') { |f| f.write(uploaded_file.read) }
      
      # Actualizar el estado a "encolado"
      @processed_file.update(status: 'queued')
      
      # Encolar el trabajo con Active Job
      ExcelProcessorJob.perform_later(@processed_file, temp_path.to_s)
      
      redirect_to file_upload_path(@processed_file), notice: 'File uploaded successfully. Processing will begin shortly.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def show
    @processed_file = ProcessedFile.find(params[:id])
    @items_sample = @processed_file.processed_items.limit(5)
    @analytics = @processed_file.analytics
  end
  
  def download
    @processed_file = ProcessedFile.find(params[:id])
    
    if @processed_file.completed? && @processed_file.result_file_path.present?
      send_excel_file(@processed_file.result_file_path, "processed_#{@processed_file.original_filename}")
    else
      redirect_to file_upload_path(@processed_file), alert: 'The file is not yet available for download.'
    end
  end
  
  def status
    @processed_file = ProcessedFile.find(params[:id])
    render json: { status: @processed_file.status }
  end
  
  def download_sample
    sample_file_path = Rails.root.join('db', 'sample_data', 'sample_inventory.xlsx')
    
    if File.exist?(sample_file_path)
      send_excel_file(sample_file_path, "sample_inventory.xlsx")
    else
      redirect_to new_file_upload_path, alert: 'The sample file is not available.'
    end
  end
  
  # NUEVO: Vista de remapeo
  def remap
    @processed_file = ProcessedFile.find(params[:id])
    
    # Solo permitir remapeo de archivos completados
    unless @processed_file.completed?
      redirect_to file_upload_path(@processed_file), alert: 'Only fully processed files can be remapped.'
      return
    end
    
    # Verificar que el archivo original esté disponible
    unless @processed_file.original_file.attached?
      redirect_to file_upload_path(@processed_file), alert: 'Original file not available for remapping.'
      return
    end
    
    # Leer headers del archivo original
    temp_file = Tempfile.new(['headers', File.extname(@processed_file.original_filename)], encoding: 'ascii-8bit')
    begin
      temp_file.binmode  # Importante: modo binario
      temp_file.write(@processed_file.original_file.download)
      temp_file.rewind
      
      spreadsheet = open_spreadsheet_from_tempfile(temp_file)
      all_headers = spreadsheet.row(1)
      
      # Preparar datos para la vista con búsqueda
      @search_query = params[:search]
      items_query = @processed_file.processed_items
      
      if @search_query.present?
        items_query = items_query.where(
          "item ILIKE ? OR description ILIKE ? OR commodity ILIKE ?", 
          "%#{@search_query}%", "%#{@search_query}%", "%#{@search_query}%"
        )
      end
      
      @items_sample = items_query.limit(20)
      @current_commodities = @processed_file.processed_items.distinct.pluck(:commodity).compact
      @available_commodities = CommodityReference.distinct.pluck(:level3_desc).compact.sort
      @commodity_counts = @processed_file.processed_items.group(:commodity).count
      
      # Preparar opciones para los selects (CORREGIDO: usar todas las columnas del archivo)
      @column_options = [['(not mapped)', nil]] + all_headers.compact.map { |col| [col, col] }
      @commodity_options = [['(keep current)', '']] + @available_commodities.map { |com| [com, com] }
      @current_commodity_options = [['Select commodity to change', '']] + @current_commodities.map { |com| [com, com] }
      
    ensure
      temp_file.close
      temp_file.unlink
    end
  end
  
  # NUEVO: Reprocesamiento con nuevo mapeo
  def reprocess
    @processed_file = ProcessedFile.find(params[:id])
    
    # Validaciones básicas
    unless @processed_file.completed? && @processed_file.original_file.attached?
      redirect_to file_upload_path(@processed_file), alert: 'This file cannot be reprocessed.'
      return
    end
    
    # Debug: Log what we're receiving
    Rails.logger.info "DEMO: Reprocessing started for file #{@processed_file.id}"
    Rails.logger.info "DEMO: Raw params received: #{params.inspect}"
    Rails.logger.info "DEMO: Filtered remap_params: #{remap_params.inspect}"
    
    # Actualizar estado
    @processed_file.update(status: 'processing')
    
    # Encolar trabajo de reprocesamiento con parámetros
    ExcelProcessorJob.perform_later(@processed_file, nil, remap_params)
    
    redirect_to file_upload_path(@processed_file), notice: 'Reprocessing started with remapping. Changes will be applied shortly.'
  end

  def export_preview
    @processed_file = ProcessedFile.find(params[:id])
    filters = JSON.parse(params[:filters]) rescue {}
    
    # Apply filters and count
    items_query = apply_export_filters(@processed_file.processed_items, filters)
    count = items_query.count
    
    render json: { count: count }
  end

  def export_filtered
    @processed_file = ProcessedFile.find(params[:id])
    filters = JSON.parse(params[:filters]) rescue {}
    
    # Debug: Log what filters we received
    Rails.logger.info "🔍 [EXPORT] Received filters: #{filters.inspect}"
    
    # Apply filters
    items_query = apply_export_filters(@processed_file.processed_items, filters)
    items_count = items_query.count
    
    Rails.logger.info "🔍 [EXPORT] Filtered items count: #{items_count}"
    
    # Generate filtered Excel file using the full generator
    filtered_file_path = generate_full_filtered_excel(items_query)
    
    send_excel_file(filtered_file_path, "filtered_#{@processed_file.original_filename}")
  end
  
  private
  
  def file_params
    params.require(:file_upload).permit(:file)
  end
  
  # NUEVO: Parámetros para remapeo
  def remap_params
    params.require(:remap).permit(
      column_mapping: {},
      line_remapping: {}
    )
  end
  
  # Helper para enviar archivos Excel
  def send_excel_file(file_path, filename)
    send_file file_path,
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment',
              filename: filename
  end
  
  # Helper para abrir spreadsheet desde tempfile
  def open_spreadsheet_from_tempfile(temp_file)
    case File.extname(@processed_file.original_filename).downcase
    when '.csv'
      Roo::CSV.new(temp_file.path)
    when '.xls'
      Roo::Excel.new(temp_file.path)
    when '.xlsx'
      Roo::Excelx.new(temp_file.path)
    else
      raise "Unsupported file format: #{@processed_file.original_filename}"
    end
  end

  # Apply simple filters to items query
  def apply_export_filters(items_query, filters)
    # Scope filters - only apply if something is selected
    if filters['scope']&.any?
      items_query = items_query.where(scope: filters['scope'])
    end
    # If scope array is empty or nil, ignore this filter (show all scopes)
    
    # Commodity filters - only apply if something is selected  
    if filters['commodity']&.any?
      items_query = items_query.where(commodity: filters['commodity'])
    end
    # If commodity array is empty or nil, ignore this filter (show all commodities)
    
    # Data quality filters - basic implementation
    if filters['data']&.any?
      if filters['data'].include?('with_prices')
        items_query = items_query.where('std_cost > 0 OR last_purchase_price > 0 OR last_po > 0')
      end
      
      if filters['data'].include?('with_cross_refs')
        items_query = items_query.where.not(mfg_partno: [nil, ''])
      end
      
      if filters['data'].include?('with_demand')
        items_query = items_query.where('eau > 0')
      end
    end
    
    items_query
  end

  # Generate filtered Excel with full format (same as original)
  def generate_full_filtered_excel(items_query)
    temp_file_path = Rails.root.join('tmp', "filtered_#{@processed_file.id}_#{Time.current.to_i}.xlsx")
    
    filtered_items = items_query.to_a
    
    package = Axlsx::Package.new
    workbook = package.workbook
    
    workbook.add_worksheet(name: "Filtered Items") do |sheet|
      # Same headers as original
      headers = [
        'SFDC_QUOTE_NUMBER', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME',
        'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 
        'LAST_PO', 'EAU', 'Commodity', 'Scope', 'Part Duplication Flag',
        'Potential Coreworks Cross', 'EAR', 'EAR Threshold Status',
        'Previously Quoted', 'Quote Date', 'Previous SFDC Quote Number', 
        'Previously Quoted INX_MPN', 'Total Demand', 'Min Price'
      ]
      sheet.add_row headers
      
      # Add filtered data
      filtered_items.each do |item|
        sheet.add_row [
          item.sugar_id, item.item, item.mfg_partno, item.global_mfg_name,
          item.description, item.site, item.std_cost, item.last_purchase_price,
          item.last_po, item.eau, item.commodity, item.scope, 'Unique',
          '', item.ear_value, item.ear_threshold_status,
          'NO', '', '', '', '', ''
        ]
      end
    end
    
    package.serialize(temp_file_path)
    temp_file_path
  end
end