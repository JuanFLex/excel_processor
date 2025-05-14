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
      # Guardar el archivo en una ubicación temporal
      temp_path = Rails.root.join('tmp', "upload_#{@processed_file.id}_#{Time.current.to_i}#{File.extname(file_params[:file].original_filename)}")
      File.open(temp_path, 'wb') { |f| f.write(file_params[:file].read) }
      
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
      send_file @processed_file.result_file_path, 
                type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                disposition: 'attachment',
                filename: "processed_#{@processed_file.original_filename}"
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
      send_file sample_file_path, 
                type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                disposition: 'attachment',
                filename: "sample_inventory.xlsx"
    else
      redirect_to new_file_upload_path, alert: 'El archivo de ejemplo no está disponible.'
    end
  end
  
  private
  
  def file_params
    params.require(:file_upload).permit(:file)
  end
end