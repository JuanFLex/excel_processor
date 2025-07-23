class OpenaiService
  EMBEDDING_MODEL = "text-embedding-3-small"
  COMPLETION_MODEL = "gpt-4-turbo"
  
  # Cache en memoria para evitar recalcular embeddings frecuentes
  @embeddings_cache = {}
  
  # Rate limiting para proteger contra desactivación de embeddings
  @tokens_per_minute = 0
  @minute_start = Time.current.beginning_of_minute
  TOKEN_LIMIT_PER_MINUTE = 250_000
  
  class << self
    attr_accessor :embeddings_cache, :tokens_per_minute, :minute_start
    
    def get_embeddings(texts)
      # Switch a mock si está configurado
      if ENV['MOCK_OPENAI'] == 'true'
        return MockOpenaiService.get_embeddings(texts)
      end
      
      return [] if texts.empty?
      
      # Filtrar textos que ya están en caché
      uncached_texts = []
      cached_embeddings = []
      
      texts.each_with_index do |text, index|
        sanitized_text = text.to_s.strip
        
        # Buscar primero en caché de memoria
        if @embeddings_cache.key?(sanitized_text)
          cached_embeddings[index] = @embeddings_cache[sanitized_text]
        else
          # Buscar en base de datos
          db_embedding = find_embedding_in_db(sanitized_text)
          if db_embedding
            cached_embeddings[index] = db_embedding
            @embeddings_cache[sanitized_text] = db_embedding
            Rails.logger.info "💾 [BD CACHE] Embedding encontrado para: #{sanitized_text[0..30]}..."
          else
            uncached_texts << { text: sanitized_text, index: index }
          end
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
        
        # Rate limiting: verificar y esperar si es necesario
        total_tokens = batch_texts.sum { |text| estimate_tokens(text) }
        check_and_wait_if_needed(total_tokens)
        
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
      # Switch a mock si está configurado
      if ENV['MOCK_OPENAI'] == 'true'
        return MockOpenaiService.identify_columns(sample_rows, target_columns)
      end
      
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
      
      # Update the prompt to include information about data types
      prompt = <<~PROMPT
        I need to identify columns in an Excel file with the following headers:
        #{headers.join(", ")}
        
        Here are some sample rows:
        #{sample_data.map { |row| row.map { |k, v| "#{k}: #{v}" }.join(", ") }.join("\n")}
        
        The target columns I need to map are:
        - SUGAR_ID: An identifier (string)
        - ITEM: An item code (string)
        - MFG_PARTNO: Part number (string)
        - GLOBAL_MFG_NAME: Manufacturer name (string)
        - DESCRIPTION: Item description (string)
        - SITE: Location (string)
        - STD_COST: Standard cost (number/price)
        - LAST_PURCHASE_PRICE: Last purchase price (number/price)
        - LAST_PO: Last purchase order price (number/price, NOT a date)
        - EAU: Annual Estimated Usage (integer)
        
        It is VERY IMPORTANT that the columns LAST_PO, STD_COST, and LAST_PURCHASE_PRICE MUST be numeric values (prices), NOT dates.
        
        Return the result as a JSON with the format {"target_column": "current_header"}.
        If you cannot identify a match for a target column, use null as the value.
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
      # Switch a mock si está configurado
      if ENV['MOCK_OPENAI'] == 'true'
        return MockOpenaiService.get_embedding_for_text(text)
      end
      
      # Truncar textos largos para reducir tokens
      truncated_text = text.to_s.strip
      truncated_text = truncated_text[0...1000] if truncated_text.length > 1000
      
      embeddings = get_embeddings([truncated_text])
      embeddings.first
    end
    
    private
    
    # Buscar embedding existente en base de datos
    def find_embedding_in_db(text)
      ProcessedItem.where("description = ? AND embedding IS NOT NULL", text).first&.embedding
    end
    
    # Estimar tokens para text-embedding-3-small (aprox 1 token = 4 caracteres)
    def estimate_tokens(text)
      (text.to_s.length / 4.0).ceil
    end
    
    # Verificar rate limit y esperar si es necesario para proteger embeddings
    def check_and_wait_if_needed(estimated_tokens)
      current_minute = Time.current.beginning_of_minute
      
      # Reset contador si cambió el minuto
      if current_minute > @minute_start
        @tokens_per_minute = 0
        @minute_start = current_minute
      end
      
      # Si excedería el límite, esperar hasta el próximo minuto
      if @tokens_per_minute + estimated_tokens > TOKEN_LIMIT_PER_MINUTE
        sleep_time = 60 - Time.current.sec + 1 # +1 para estar seguro
        Rails.logger.warn "⏳ [RATE LIMIT] Se alcanzó el límite de #{TOKEN_LIMIT_PER_MINUTE} tokens/min. Esperando #{sleep_time}s para proteger embeddings..."
        sleep(sleep_time)
        @tokens_per_minute = 0
        @minute_start = Time.current.beginning_of_minute
      end
      
      # Actualizar contador
      @tokens_per_minute += estimated_tokens
      
      # Log ocasional para monitoreo
      if @tokens_per_minute % 50_000 < estimated_tokens
        Rails.logger.info "📊 [RATE LIMIT] Tokens usados en este minuto: #{@tokens_per_minute}/#{TOKEN_LIMIT_PER_MINUTE}"
      end
    end
  end
end