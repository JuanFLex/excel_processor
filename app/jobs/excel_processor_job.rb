class ExcelProcessorJob < ApplicationJob
  queue_as :default
  
  discard_on StandardError do |job, error|
    # Actualizar el estado del archivo en caso de error
    processed_file = job.arguments.first
    processed_file.update(status: 'failed')
    
    # Registrar el error
    Rails.logger.error("Error in ExcelProcessorJob: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n"))
  end
  
  def perform(processed_file, file_path)
    # Verificar si el archivo existe
    unless File.exist?(file_path)
      processed_file.update(status: 'failed')
      return
    end
    
    # Crear un archivo temporal
    temp_file = Tempfile.new(['uploaded', File.extname(processed_file.original_filename)])
    
    begin
      # Copiar el contenido al archivo temporal
      FileUtils.cp(file_path, temp_file.path)
      
      # Crear un objeto de archivo que Rails pueda procesar
      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        filename: processed_file.original_filename,
        type: mime_type_for(processed_file.original_filename),
        tempfile: temp_file
      )
      
      # Procesar el archivo
      processor = ExcelProcessorService.new(processed_file)
      processor.process_upload(uploaded_file)
      
      # Limpiar después de procesar
      FileUtils.rm(file_path) if File.exist?(file_path)
    rescue => e
      # Registrar error y actualizar estado
      Rails.logger.error("Error in ExcelProcessorJob: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      
      processed_file.update(status: 'failed')
      
      # Re-lanzar la excepción para que el manejador discard_on la capture
      raise e
    ensure
      # Eliminar el archivo temporal
      temp_file.close
      temp_file.unlink
    end
  end
  
  private
  
  def mime_type_for(filename)
    case File.extname(filename).downcase
    when '.csv'
      'text/csv'
    when '.xls'
      'application/vnd.ms-excel'
    when '.xlsx'
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    else
      'application/octet-stream'
    end
  end
end