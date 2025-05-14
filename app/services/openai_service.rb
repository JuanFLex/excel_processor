class OpenaiService
  EMBEDDING_MODEL = "text-embedding-3-small"
  COMPLETION_MODEL = "gpt-4-turbo"
  
  # Cache en memoria para evitar recalcular embeddings frecuentes
  @embeddings_cache = {}
  
  class << self
    attr_accessor :embeddings_cache
    
    def get_embeddings(texts)
      return [] if texts.empty?
      
      # Filtrar textos que ya están en caché
      uncached_texts = []
      cached_embeddings = []
      
      texts.each_with_index do |text, index|
        sanitized_text = text.to_s.strip
        
        if @embeddings_cache.key?(sanitized_text)
          cached_embeddings[index] = @embeddings_cache[sanitized_text]
        else
          uncached_texts << { text: sanitized_text, index: index }
        end
      end
      
      # Si todo está en caché, devolver los embeddings cacheados
      if uncached_texts.empty?
        return texts.map.with_index { |_, i| cached_embeddings[i] }
      end
      
      # Procesar solo los textos que no están en caché
      client = OpenAI::Client.new
      
      # Agrupar textos en lotes de 20 para reducir llamadas a la API
      result_embeddings = Array.new(texts.size)
      
      # Copiar los embeddings cacheados al array de resultados
      cached_embeddings.each_with_index do |embedding, index|
        result_embeddings[index] = embedding if embedding
      end
      
      # Procesar textos no cacheados en lotes
      uncached_texts.each_slice(20) do |batch|
        batch_texts = batch.map { |item| item[:text] }
        
        response = client.embeddings(
          parameters: {
            model: EMBEDDING_MODEL,
            input: batch_texts
          }
        )
        
        # Procesar respuesta
        if response["data"] && response["data"].is_a?(Array)
          response["data"].each_with_index do |item, i|
            text = batch_texts[i]
            index = batch[i][:index]
            embedding = item["embedding"]
            
            # Guardar en caché
            @embeddings_cache[text] = embedding
            
            # Guardar en resultado
            result_embeddings[index] = embedding
          end
        else
          Rails.logger.error("Error getting embeddings: #{response.inspect}")
        end
      end
      
      # Limpiar caché si es demasiado grande (más de 1000 entradas)
      if @embeddings_cache.size > 1000
        @embeddings_cache.clear
      end
      
      result_embeddings
    rescue => e
      Rails.logger.error("OpenAI API error: #{e.message}")
      []
    end
    
    def identify_columns(sample_rows, target_columns)
      return {} if sample_rows.empty?
      
      client = OpenAI::Client.new
      
      # Limitamos la cantidad de filas de muestra para reducir tokens
      sample_data = sample_rows.map(&:to_h).first(3)
      headers = sample_data.first.keys
      
      # Limitar el tamaño de las descripciones para reducir tokens
      sample_data_truncated = sample_data.map do |row|
        row.transform_values do |value|
          value.is_a?(String) && value.length > 100 ? value[0...100] + "..." : value
        end
      end
      
      # Crear un prompt más conciso
      prompt = <<~PROMPT
        Headers: #{headers.join(", ")}
        
        Sample rows:
        #{sample_data_truncated.map { |row| row.map { |k, v| "#{k}: #{v}" }.join(" | ") }.join("\n")}
        
        Target columns: #{target_columns.join(", ")}
        
        Map each target column to one of the existing headers. Return a JSON with format {"target_column": "matching_header"} or null if no match.
      PROMPT
      
      response = client.chat(
        parameters: {
          model: COMPLETION_MODEL,
          messages: [
            { role: "system", content: "You are a data analysis expert specializing in mapping Excel columns." },
            { role: "user", content: prompt }
          ],
          response_format: { type: "json_object" },
          max_tokens: 500  # Limitar tokens de respuesta
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
    
    def get_embedding_for_text(text)
      # Truncar textos largos para reducir tokens
      truncated_text = text.to_s.strip
      truncated_text = truncated_text[0...1000] if truncated_text.length > 1000
      
      embeddings = get_embeddings([truncated_text])
      embeddings.first
    end
  end
end