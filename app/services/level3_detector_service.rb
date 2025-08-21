class Level3DetectorService
  
  # Detecta si el archivo tiene una columna que contiene level3_desc o global_comm_code_desc
  def self.detect_level3_column(sample_rows)
    new.detect_level3_column(sample_rows)
  end
  
  # Nuevo método para detectar GLOBAL_COMM_CODE_DESC específicamente
  def self.detect_global_comm_code_column(sample_rows)
    new.detect_global_comm_code_column(sample_rows)
  end
  
  # Detectar LEVEL1_DESC específicamente
  def self.detect_level1_column(sample_rows)
    new.detect_level1_column(sample_rows)
  end
  
  # Detectar LEVEL2_DESC específicamente
  def self.detect_level2_column(sample_rows)
    new.detect_level2_column(sample_rows)
  end
  
  def detect_level3_column(sample_rows)
    return nil if sample_rows.empty?
    
    headers = sample_rows.first.keys
    
    # Buscar columnas que podrían contener level3_desc
    potential_columns = headers.select do |header|
      header_normalized = header.to_s.downcase.strip
      # Buscar exactamente level3 o level_3
      header_normalized.include?('level3') || 
      header_normalized.include?('level_3') || 
      header_normalized.include?('level 3')
    end
    
    return nil if potential_columns.empty?
    
    # Si encontramos columnas potenciales, verificar contenido
    best_column = find_best_level3_column(sample_rows, potential_columns)
    
    if best_column
      Rails.logger.info "🎯 [LEVEL3] Detected exact Level3 column: #{best_column}"
      return best_column
    end
    
    nil
  end
  
  def detect_global_comm_code_column(sample_rows)
    return nil if sample_rows.empty?
    
    headers = sample_rows.first.keys
    
    # Buscar columnas que podrían contener global_comm_code_desc
    potential_columns = headers.select do |header|
      header_normalized = header.to_s.downcase.strip
      # Buscar exactamente global_comm_code o variantes similares
      header_normalized.include?('global_comm_code') || 
      header_normalized.include?('global_commodity_code') || 
      header_normalized.include?('global comm code')
    end
    
    return nil if potential_columns.empty?
    
    # Si encontramos columnas potenciales, verificar contenido
    best_column = find_best_global_comm_code_column(sample_rows, potential_columns)
    
    if best_column
      Rails.logger.info "🎯 [GLOBAL_COMM_CODE] Detected exact Global Commodity Code column: #{best_column}"
      return best_column
    end
    
    nil
  end
  
  def detect_level1_column(sample_rows)
    return nil if sample_rows.empty?
    
    headers = sample_rows.first.keys
    
    # Buscar columnas que podrían contener level1_desc
    potential_columns = headers.select do |header|
      header_normalized = header.to_s.downcase.strip
      # Buscar exactamente level1 o level_1
      header_normalized.include?('level1') || 
      header_normalized.include?('level_1') || 
      header_normalized.include?('level 1')
    end
    
    return nil if potential_columns.empty?
    
    # Si encontramos columnas potenciales, verificar contenido
    best_column = find_best_level1_column(sample_rows, potential_columns)
    
    if best_column
      Rails.logger.info "🎯 [LEVEL1] Detected exact Level1 column: #{best_column}"
      return best_column
    end
    
    nil
  end
  
  def detect_level2_column(sample_rows)
    return nil if sample_rows.empty?
    
    headers = sample_rows.first.keys
    
    # Buscar columnas que podrían contener level2_desc
    potential_columns = headers.select do |header|
      header_normalized = header.to_s.downcase.strip
      # Buscar exactamente level2 o level_2
      header_normalized.include?('level2') || 
      header_normalized.include?('level_2') || 
      header_normalized.include?('level 2')
    end
    
    return nil if potential_columns.empty?
    
    # Si encontramos columnas potenciales, verificar contenido
    best_column = find_best_level2_column(sample_rows, potential_columns)
    
    if best_column
      Rails.logger.info "🎯 [LEVEL2] Detected exact Level2 column: #{best_column}"
      return best_column
    end
    
    nil
  end
  
  private
  
  def find_best_level3_column(sample_rows, potential_columns)
    # Obtener una muestra más grande de level3_desc para archivos pequeños
    reference_level3_samples = CommodityReference.pluck(:level3_desc).compact
    
    return potential_columns.first if reference_level3_samples.empty?
    
    # Para cada columna potencial, calcular similitud con nuestros level3_desc
    column_scores = {}
    
    potential_columns.each do |column|
      score = calculate_column_similarity(sample_rows, column, reference_level3_samples)
      column_scores[column] = score
    end
    
    # Retornar la columna con mayor score (si supera umbral)
    best_column = column_scores.max_by { |_, score| score }
    
    if best_column && best_column[1] > 0.5  # 50% de valores únicos deben coincidir
      return best_column[0]
    end
    
    nil
  end
  
  def calculate_column_similarity(sample_rows, column, reference_samples)
    # Extraer valores únicos de la columna (NO repetir comparaciones)
    column_values = sample_rows.map { |row| row[column].to_s.strip }.reject(&:empty?).uniq
    
    return 0 if column_values.empty?
    
    # Contar cuántos valores únicos del archivo existen en la referencia
    matches = column_values.count do |file_val|
      reference_samples.any? do |ref_val|
        file_val.downcase.gsub(/\s+/, '') == ref_val.downcase.gsub(/\s+/, '')
      end
    end
    
    # Retornar porcentaje de valores únicos que coinciden
    matches.to_f / column_values.size  # 2/2 = 1.0 para tu archivo
  end
  
  def find_best_level1_column(sample_rows, potential_columns)
    # Obtener muestras de level1_desc para comparación
    reference_level1_samples = CommodityReference.pluck(:level1_desc).compact.uniq
    
    return potential_columns.first if reference_level1_samples.empty?
    
    # Para cada columna potencial, calcular similitud con nuestros level1_desc
    column_scores = {}
    
    potential_columns.each do |column|
      score = calculate_column_similarity(sample_rows, column, reference_level1_samples)
      column_scores[column] = score
    end
    
    # Retornar la columna con mayor score (si supera umbral)
    best_column = column_scores.max_by { |_, score| score }
    
    if best_column && best_column[1] > 0.3  # 30% umbral más bajo para level1 (más genérico)
      return best_column[0]
    end
    
    nil
  end
  
  def find_best_level2_column(sample_rows, potential_columns)
    # Obtener muestras de level2_desc para comparación
    reference_level2_samples = CommodityReference.pluck(:level2_desc).compact.uniq
    
    return potential_columns.first if reference_level2_samples.empty?
    
    # Para cada columna potencial, calcular similitud con nuestros level2_desc
    column_scores = {}
    
    potential_columns.each do |column|
      score = calculate_column_similarity(sample_rows, column, reference_level2_samples)
      column_scores[column] = score
    end
    
    # Retornar la columna con mayor score (si supera umbral)
    best_column = column_scores.max_by { |_, score| score }
    
    if best_column && best_column[1] > 0.4  # 40% umbral para level2
      return best_column[0]
    end
    
    nil
  end
  
  def find_best_global_comm_code_column(sample_rows, potential_columns)
    # Similar lógica para global_comm_code_desc
    reference_samples = CommodityReference.pluck(:global_comm_code_desc).compact.uniq
    
    return potential_columns.first if reference_samples.empty?
    
    column_scores = {}
    
    potential_columns.each do |column|
      score = calculate_column_similarity(sample_rows, column, reference_samples)
      column_scores[column] = score
    end
    
    best_column = column_scores.max_by { |_, score| score }
    
    if best_column && best_column[1] > 0.5  # 50% umbral para global_comm_code
      return best_column[0]
    end
    
    nil
  end
end