class FileUploadsController < ApplicationController
  def index
    @processed_files = ProcessedFile.order(created_at: :desc).limit(10)
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
      
      redirect_to file_upload_path(@processed_file), notice: 'Archivo subido correctamente. El procesamiento comenzará en breve.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def show
    @processed_file = ProcessedFile.find(params[:id])
    @items_sample = @processed_file.processed_items.limit(5)
  end
  
  def download
    @processed_file = ProcessedFile.find(params[:id])
    
    if @processed_file.completed? && @processed_file.result_file_path.present?
      send_excel_file(@processed_file.result_file_path, "processed_#{@processed_file.original_filename}")
    else
      redirect_to file_upload_path(@processed_file), alert: 'El archivo aún no está disponible para descarga.'
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
      redirect_to new_file_upload_path, alert: 'El archivo de ejemplo no está disponible.'
    end
  end
  
  # NUEVO: Vista de remapeo
  def remap
    @processed_file = ProcessedFile.find(params[:id])
    
    # Solo permitir remapeo de archivos completados
    unless @processed_file.completed?
      redirect_to file_upload_path(@processed_file), alert: 'Solo se pueden remapear archivos procesados completamente.'
      return
    end
    
    # Verificar que el archivo original esté disponible
    unless @processed_file.original_file.attached?
      redirect_to file_upload_path(@processed_file), alert: 'Archivo original no disponible para remapeo.'
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
      
      # Preparar datos para la vista
      @items_sample = @processed_file.processed_items.limit(10)
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
      redirect_to file_upload_path(@processed_file), alert: 'No se puede reprocesar este archivo.'
      return
    end
    
    # Actualizar estado
    @processed_file.update(status: 'processing')
    
    # Encolar trabajo de reprocesamiento con parámetros
    ExcelProcessorJob.perform_later(@processed_file, nil, remap_params)
    
    redirect_to file_upload_path(@processed_file), notice: 'Reprocesamiento iniciado. Los cambios se aplicarán en breve.'
  end
  
  private
  
  def file_params
    params.require(:file_upload).permit(:file)
  end
  
  # NUEVO: Parámetros para remapeo
  def remap_params
    params.require(:remap).permit(
      column_mapping: {},
      commodity_changes: {},
      custom_mapping: [:from, :to, :scope]
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
      raise "Formato de archivo no soportado: #{@processed_file.original_filename}"
    end
  end
end