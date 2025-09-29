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

    # Guardar configuración del Component Grade filtering
    @processed_file.include_medical_auto_grades = file_params[:include_medical_auto_grades] == '1'
    
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

    # Pre-cargar commodity references en batch para evitar N+1 en la vista
    if @processed_file.unique_items_array.any?
      unique_commodities = @processed_file.unique_items_array.map(&:commodity).uniq.compact.reject(&:blank?)
      @commodity_to_level1_cache = CommodityReference.find_commodities_batch(unique_commodities)
        .transform_values { |ref| ref&.level1_desc || 'Unknown Level 1' }
    else
      @commodity_to_level1_cache = {}
    end

    # Pre-cargar SQL caches para cálculos de EAR en la vista
    @sql_caches = @processed_file.send(:load_sql_caches_for_analytics)
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

  # AJAX endpoint para lookup de oportunidades
  def lookup_opportunity
    opportunity_number = params[:opportunity_number]

    if opportunity_number.blank?
      render json: { error: 'Opportunity number is required' }, status: :bad_request
      return
    end

    begin
      opportunity_data = ItemLookup.lookup_opportunity(opportunity_number)

      if opportunity_data
        render json: { success: true, data: opportunity_data }
      else
        render json: { success: false, message: 'Opportunity not found' }
      end
    rescue => e
      Rails.logger.error "Error in opportunity lookup: #{e.message}"
      render json: { error: 'Database error occurred' }, status: :internal_server_error
    end
  end

  private
  
  def file_params
    params.require(:file_upload).permit(:file, :volume_multiplier_enabled, :volume_multiplier, :enable_total_demand_lookup, :include_medical_auto_grades)
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
    # FIXED: Handle scope normalization like the model methods
    if filters['scope']&.any?
      # Get all distinct scopes from the database
      all_scopes = items_query.distinct.pluck(:scope).compact

      # Find which raw scopes normalize to the selected filters
      matching_scopes = all_scopes.select do |raw_scope|
        normalized = ProcessedFile.normalize_scope(raw_scope)
        filters['scope'].include?(normalized)
      end

      items_query = items_query.where(scope: matching_scopes)
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

  # Generate filtered Excel with full format using centralized service
  def generate_full_filtered_excel(items_query)
    Rails.logger.info "🔄 [EXPORT] Generating filtered Excel using ExcelGeneratorService"

    filtered_items = items_query.to_a
    excel_generator = ExcelGeneratorService.new(@processed_file)
    excel_generator.generate_excel_file(filtered_items)
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

end