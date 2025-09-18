require 'set'

class FileUploadsController < ApplicationController
  before_action :require_admin_for_delete, only: [:destroy]
  def index
    @processed_files = ProcessedFile.order(created_at: :desc).page(params[:page]).per(10)
  end
  
  def new
    @processed_file = ProcessedFile.new
  end
  
  def create
    @processed_file = ProcessedFile.new(original_filename: file_params[:file].original_filename, status: 'pending')
    
    # Guardar configuración del multiplicador de volumen
    if file_params[:volume_multiplier_enabled] == '1' && file_params[:volume_multiplier].present?
      @processed_file.volume_multiplier = file_params[:volume_multiplier].to_i
    end
    
    # Guardar configuración del Total Demand lookup
    @processed_file.enable_total_demand_lookup = file_params[:enable_total_demand_lookup] == '1'
    
    if @processed_file.save
      # ACTUALIZADO: Guardar archivo original en Active Storage
      uploaded_file = file_params[:file]
      @processed_file.original_file.attach(uploaded_file)
      
      # Guardar el archivo en una ubicación temporal para procesamiento
      temp_path = Rails.root.join('tmp', "upload_#{@processed_file.id}_#{Time.current.to_i}#{File.extname(uploaded_file.original_filename)}")
      
      # CORREGIDO: Rewind el archivo antes de leer
      uploaded_file.rewind
      File.open(temp_path, 'wb') { |f| f.write(uploaded_file.read) }
      
      # Actualizar el estado a "column preview" 
      @processed_file.update(status: 'column_preview')
      
      # Generar column mapping con OpenAI (proceso rápido)
      generate_column_mapping_preview(@processed_file, temp_path.to_s)
      
      redirect_to file_upload_path(@processed_file), notice: 'File uploaded successfully. Please review the column mapping.'
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

  def approve_mapping
    @processed_file = ProcessedFile.find(params[:id])
    
    if @processed_file.column_preview?
      # Start full processing
      @processed_file.update(status: 'queued')
      
      # Get the temp file path using existing pattern
      temp_path_pattern = Rails.root.join('tmp', "upload_#{@processed_file.id}_*")
      actual_temp_path = Dir.glob(temp_path_pattern.to_s).first
      
      if actual_temp_path
        ExcelProcessorJob.perform_later(@processed_file, actual_temp_path)
        redirect_to file_upload_path(@processed_file), notice: 'Processing started!'
      else
        redirect_to file_upload_path(@processed_file), alert: 'File not found. Please upload again.'
      end
    else
      redirect_to file_upload_path(@processed_file), alert: 'File is not in preview state.'
    end
  end

  def update_mapping
    @processed_file = ProcessedFile.find(params[:id])
    
    if @processed_file.column_preview? && params[:column_mapping].present?
      # Update the column mapping
      @processed_file.update(column_mapping: params[:column_mapping])
      
      render json: { success: true, message: 'Mapping updated' }
    else
      render json: { success: false, message: 'Invalid request' }
    end
  end

  def destroy
    @processed_file = ProcessedFile.find(params[:id])
    filename = @processed_file.original_filename
    
    begin
      # Delete associated file if exists
      if @processed_file.result_file_path.present? && File.exist?(@processed_file.result_file_path)
        File.delete(@processed_file.result_file_path)
      end
      
      # Delete the processed file record (cascades to processed_items)
      @processed_file.destroy
      
      redirect_to file_uploads_path, notice: "File '#{filename}' and all its data have been deleted successfully."
    rescue => e
      Rails.logger.error "Error deleting file #{@processed_file.id}: #{e.message}"
      redirect_to file_uploads_path, alert: "Error deleting file: #{e.message}"
    end
  end
  
  private
  
  def file_params
    params.require(:file_upload).permit(:file, :volume_multiplier_enabled, :volume_multiplier, :enable_total_demand_lookup)
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
      begin
        Roo::Excel.new(temp_file.path)
      rescue => e
        Rails.logger.error "Error opening XLS file in remap: #{e.message}"
        raise "Error reading XLS file: #{e.message}. Please ensure the file is valid."
      end
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
      
      # Define styles matching original Excel format
      header_style = workbook.styles.add_style(
        bg_color: "FA4616",  # Orange for quote form columns
        fg_color: "FFFFFF",
        b: true,
        alignment: { horizontal: :center },
        font_name: "Century Gothic",
        sz: 11
      )

      auxiliary_style = workbook.styles.add_style(
        bg_color: "5498c6",  # Blue for auxiliary columns
        fg_color: "FFFFFF", 
        b: true,
        alignment: { horizontal: :center },
        font_name: "Century Gothic",
        sz: 11
      )
      
      # Define which columns are from Quote form (use ORANGE)
      quote_form_columns = ['ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 'LAST_PO', 'EAU', 'Commodity']
      
      # Create array of styles based on column name
      header_styles = headers.map do |header|
        quote_form_columns.include?(header) ? header_style : auxiliary_style
      end

      # Add header with column-specific styling
      sheet.add_row headers, style: header_styles
      
      # Add filtered data with real SQL lookups (optimized with batch processing)
      # Pre-load all SQL data in batches to avoid N+1 queries
      sql_caches = load_sql_caches_for_export(filtered_items)
      
      item_tracker = Set.new
      filtered_items.each do |item|
        # Track unique items (same logic as main generation)
        unique_flg = item_tracker.include?(item.item) ? 'AML' : 'Unique'
        item_tracker.add(item.item)
        
        # Lookup data from pre-loaded caches (optimized batch processing)
        total_demand_data = sql_caches[:total_demand][item.item.to_s.strip] if sql_caches[:total_demand]
        min_price_data = sql_caches[:min_price][item.item.to_s.strip] if sql_caches[:min_price]
        cross_ref_mpn = sql_caches[:cross_ref][item.mfg_partno.to_s.strip] if sql_caches[:cross_ref] && item.mfg_partno
        
        sheet.add_row [
          item.sugar_id, item.item, item.mfg_partno, item.global_mfg_name,
          item.description, item.site, item.std_cost, item.last_purchase_price,
          item.last_po, item.eau, item.commodity, item.scope, unique_flg,
          cross_ref_mpn, item.ear_value(total_demand_data, min_price_data), item.ear_threshold_status(total_demand_data, min_price_data),
          'NO', '', '', '', 
          total_demand_data, min_price_data
        ]
      end
    end
    
    package.serialize(temp_file_path)
    temp_file_path
  end

  # Generate column mapping preview (fast process)
  def generate_column_mapping_preview(processed_file, temp_path)
    begin
      # Read Excel file
      spreadsheet = open_spreadsheet_from_temp_path(temp_path)
      header = spreadsheet.row(1)
      
      # Get sample rows for OpenAI
      sample_rows = []
      (2..6).each do |i|
        row = Hash[header.zip(spreadsheet.row(i))]
        sample_rows << row if i <= spreadsheet.last_row
      end
      
      # Use OpenAI to identify columns (fast)
      column_mapping = OpenaiService.identify_columns(sample_rows, ExcelProcessorConfig::TARGET_COLUMNS)
      
      # Detect commodity columns
      %w[LEVEL1_DESC LEVEL2_DESC LEVEL3_DESC GLOBAL_COMM_CODE_DESC].each do |column_type|
        detected_column = detect_commodity_column_simple(sample_rows, column_type)
        column_mapping[column_type] = detected_column if detected_column
      end
      
      # Save mapping
      processed_file.update(column_mapping: column_mapping)
      
    rescue => e
      Rails.logger.error "Error generating column mapping preview: #{e.message}"
      processed_file.update(status: 'failed', error_message: e.message)
    end
  end

  # Simple helper for temp file reading
  def open_spreadsheet_from_temp_path(temp_path)
    case File.extname(temp_path).downcase
    when '.csv'
      Roo::CSV.new(temp_path)
    when '.xls'
      begin
        Roo::Excel.new(temp_path)
      rescue => e
        Rails.logger.error "Error opening XLS file from temp path: #{e.message}"
        raise "Error reading XLS file: #{e.message}. Please ensure the file is valid."
      end
    when '.xlsx'
      Roo::Excelx.new(temp_path)
    else
      raise "Unsupported file format"
    end
  end

  # Simple commodity column detection
  def detect_commodity_column_simple(sample_rows, column_type)
    return nil if sample_rows.empty?
    
    sample_rows.first&.keys&.find { |header| header.to_s.upcase.include?(column_type.gsub('_DESC', '')) }
  end

  def require_admin_for_delete
    unless current_user&.admin?
      redirect_to file_uploads_path, alert: 'Only administrators can delete files.'
    end
  end

  # Optimized batch loading of SQL caches for export functionality
  def load_sql_caches_for_export(filtered_items)
    caches = {
      total_demand: {},
      min_price: {},
      cross_ref: {}
    }
    
    # Skip if using mock SQL server
    return caches if ENV['MOCK_SQL_SERVER'] == 'true'
    
    # Extract unique items and MPNs
    unique_items = filtered_items.map { |item| item.item.to_s.strip }.compact.uniq
    unique_mpns = filtered_items.map { |item| item.mfg_partno.to_s.strip }.compact.uniq.reject(&:empty?)
    
    Rails.logger.info "🔍 [EXPORT] Loading SQL caches for #{unique_items.size} unique items and #{unique_mpns.size} unique MPNs"
    
    begin
      # Load Total Demand cache (only if enabled for this processed file)
      if @processed_file.enable_total_demand_lookup && unique_items.any?
        unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_items|
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
        Rails.logger.info "🔍 [EXPORT] Loaded #{caches[:total_demand].size} Total Demand entries"
      end
      
      # Load Min Price cache
      if unique_items.any?
        unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_items|
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
        Rails.logger.info "🔍 [EXPORT] Loaded #{caches[:min_price].size} Min Price entries"
      end
      
      # Load Cross Reference cache
      if unique_mpns.any?
        unique_mpns.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_mpns|
          quoted_mpns = batch_mpns.map { |mpn| "'#{mpn.gsub("'", "''")}'" }.join(',')
          
          result = ItemLookup.connection.select_all(
            "SELECT CROSS_REF_MPN, INFINEX_MPN 
             FROM INX_dataLabCrosses 
             WHERE CROSS_REF_MPN IN (#{quoted_mpns}) AND INFINEX_MPN IS NOT NULL"
          )
          
          result.rows.each do |row|
            caches[:cross_ref][row[0]] = row[1]
          end
        end
        Rails.logger.info "🔍 [EXPORT] Loaded #{caches[:cross_ref].size} Cross Reference entries"
      end
      
    rescue => e
      Rails.logger.error "❌ [EXPORT] Error loading SQL caches: #{e.message}"
      # Return empty caches so export continues without SQL data
    end
    
    caches
  end
end