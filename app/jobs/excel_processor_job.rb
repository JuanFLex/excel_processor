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
  
  def perform(processed_file, file_path = nil, manual_remap = nil)
    # NUEVO: Manejar remapeo (usar archivo de Active Storage)
    if manual_remap.present?
      Rails.logger.info "🔄 [REMAP] Starting remap processing for: #{processed_file.original_filename}"
      
      # Usar archivo original de Active Storage
      unless processed_file.original_file.attached?
        processed_file.update(status: 'failed', error_message: 'Original file not available for remap')
        return
      end
      
      # Durante remapping, necesitamos limpiar items después de extraer datos de referencia para remapping
      Rails.logger.info "🔄 [REMAP] Processing remapping - will clear items after applying remapping logic..."
      
      # Crear archivo temporal del archivo guardado
      temp_file = Tempfile.new(['remap', File.extname(processed_file.original_filename)], encoding: 'ascii-8bit')
      begin
        temp_file.binmode
        temp_file.write(processed_file.original_file.download)
        temp_file.rewind
        
        uploaded_file = ActionDispatch::Http::UploadedFile.new(
          filename: processed_file.original_filename,
          type: processed_file.original_file.content_type,
          tempfile: temp_file
        )
        
        # Procesar con remapeo
        processor = ExcelProcessorService.new(processed_file)
        processor.process_upload(uploaded_file, manual_remap)
        
        # NUEVO: Ejecutar análisis automático de IA para top EAR items después de remapeo
        if processed_file.status == 'completed'
          Rails.logger.info "🤖 [AUTO-AI] Scheduling automatic AI analysis for top EAR items after remap"
          TopEarAnalyzerJob.perform_later(processed_file.id)
        end
        
      ensure
        temp_file.close
        temp_file.unlink
      end
      
    else
      # Procesamiento original (upload nuevo)
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
        
        # NUEVO: Ejecutar análisis automático de IA para top EAR items
        if processed_file.status == 'completed'
          Rails.logger.info "🤖 [AUTO-AI] Scheduling automatic AI analysis for top EAR items"
          TopEarAnalyzerJob.perform_later(processed_file.id)
        end
        
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