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