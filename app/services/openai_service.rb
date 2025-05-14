class OpenaiService
  EMBEDDING_MODEL = "text-embedding-3-small"
  COMPLETION_MODEL = "gpt-4-turbo"
  
  def self.get_embeddings(texts)
    return [] if texts.empty?
    
    client = OpenAI::Client.new
    
    # Asegurar que todos los textos son strings
    sanitized_texts = texts.map { |text| text.to_s.strip }
    
    # Obtener embeddings de OpenAI
    response = client.embeddings(
      parameters: {
        model: EMBEDDING_MODEL,
        input: sanitized_texts
      }
    )
    
    # Extraer los embeddings de la respuesta
    if response["data"] && response["data"].is_a?(Array)
      response["data"].map { |item| item["embedding"] }
    else
      Rails.logger.error("Error getting embeddings: #{response.inspect}")
      []
    end
  rescue => e
    Rails.logger.error("OpenAI API error: #{e.message}")
    []
  end
  
  def self.identify_columns(sample_rows, target_columns)
    return {} if sample_rows.empty?
    
    client = OpenAI::Client.new
    
    # Preparar datos de muestra para el prompt
    sample_data = sample_rows.map(&:to_h).first(5)
    headers = sample_data.first.keys
    
    # Crear el prompt para identificar columnas
    prompt = <<~PROMPT
      Necesito identificar columnas en un archivo Excel con los siguientes encabezados:
      #{headers.join(", ")}
      
      Aquí hay algunas filas de muestra:
      #{sample_data.map { |row| row.map { |k, v| "#{k}: #{v}" }.join(", ") }.join("\n")}
      
      Las columnas objetivo que necesito mapear son:
      #{target_columns.join(", ")}
      
      Por favor, identifica cuál de los encabezados actuales corresponde a cada columna objetivo.
      Devuelve el resultado como un JSON con el formato {"columna_objetivo": "encabezado_actual"}.
      Si no puedes identificar una correspondencia para alguna columna objetivo, usa null como valor.
    PROMPT
    
    response = client.chat(
      parameters: {
        model: COMPLETION_MODEL,
        messages: [
          { role: "system", content: "Eres un asistente experto en análisis de datos y mapeo de columnas de Excel." },
          { role: "user", content: prompt }
        ],
        response_format: { type: "json_object" }
      }
    )
    
    # Extraer y parsear el JSON de la respuesta
    if response.dig("choices", 0, "message", "content")
      begin
        JSON.parse(response.dig("choices", 0, "message", "content"))
      rescue JSON::ParserError => e
        Rails.logger.error("Error parsing OpenAI response: #{e.message}")
        {}
      end
    else
      Rails.logger.error("Unexpected OpenAI response format: #{response.inspect}")
      {}
    end
  rescue => e
    Rails.logger.error("OpenAI API error: #{e.message}")
    {}
  end
  
  def self.get_embedding_for_text(text)
    embeddings = get_embeddings([text])
    embeddings.first
  end
end