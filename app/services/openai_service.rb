class OpenaiService
  EMBEDDING_MODEL = "text-embedding-3-small"
  COMPLETION_MODEL = "gpt-4-turbo"

  # Class-level cache persistente para embeddings (sin TTL - los embeddings no cambian)
  @@embeddings_cache = {}

  # Rate limiting para proteger contra desactivación de embeddings
  @@tokens_per_minute = 0
  @@minute_start = Time.current.beginning_of_minute
  TOKEN_LIMIT_PER_MINUTE = 250_000

  class << self
    
    def get_embeddings(texts)
      # Switch a mock si está configurado
      if ENV['MOCK_OPENAI'] == 'true'
        return MockOpenaiService.get_embeddings(texts)
      end
      
      return [] if texts.empty?
      
      # Pre-cargar embeddings de BD en batch para evitar N+1 queries
      start_time = Time.current
      db_embeddings_cache = preload_embeddings_from_db_batched(texts)
      cache_load_time = ((Time.current - start_time) * 1000).round(2)
      Rails.logger.info "⏱️ [TIMING] DB Embeddings Cache Load: #{cache_load_time}ms"
      
      # Filtrar textos que ya están en caché
      uncached_texts = []
      cached_embeddings = []
      
      texts.each_with_index do |text, index|
        sanitized_text = sanitize_text_for_embedding(text)
        
        # Buscar primero en caché de memoria
        if @@embeddings_cache.key?(sanitized_text)
          cached_embeddings[index] = @@embeddings_cache[sanitized_text]
        elsif db_embeddings_cache.key?(sanitized_text)
          # Usar caché de BD pre-cargado (evita N+1 queries)
          db_embedding = db_embeddings_cache[sanitized_text]
          cached_embeddings[index] = db_embedding
          @@embeddings_cache[sanitized_text] = db_embedding
          Rails.logger.info "💾 [BD CACHE] Embedding encontrado para: #{sanitized_text[0..30]}..."
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
            @@embeddings_cache[text] = embedding
            
            # Guardar en resultado
            result_embeddings[index] = embedding
          end
        else
          Rails.logger.error("Error getting embeddings: #{response.inspect}")
        end
      end
      
      # Limpiar caché si es demasiado grande
      if @@embeddings_cache.size > ExcelProcessorConfig::EMBEDDINGS_CACHE_LIMIT
        @@embeddings_cache.clear
        Rails.logger.info "🧹 [EMBEDDINGS CACHE] Cache cleared due to size limit (#{ExcelProcessorConfig::EMBEDDINGS_CACHE_LIMIT} entries)"
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
        - EAU: Annual Estimated Usage (integer) may be Total Demand, Total Gross Demand
        
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
      truncated_text = truncated_text[0...ExcelProcessorConfig::TEXT_TRUNCATION_LIMIT] if truncated_text.length > ExcelProcessorConfig::TEXT_TRUNCATION_LIMIT
      
      embeddings = get_embeddings([truncated_text])
      embeddings.first
    end
    
    def get_completion(prompt, max_tokens = 1500)
      # Switch a mock si está configurado
      if ENV['MOCK_OPENAI'] == 'true'
        return MockOpenaiService.get_completion(prompt, max_tokens)
      end
      
      client = OpenAI::Client.new
      
      response = client.chat(
        parameters: {
          model: COMPLETION_MODEL,
          messages: [
            { role: "system", content: "You are an expert in electronic components classification and analysis. You provide detailed, accurate analysis with specific recommendations." },
            { role: "user", content: prompt }
          ],
          max_tokens: max_tokens,
          temperature: 0.1  # Low temperature for consistent analysis
        }
      )
      
      response.dig("choices", 0, "message", "content")
    rescue => e
      Rails.logger.error("OpenAI completion error: #{e.message}")
      "Error analyzing: #{e.message}"
    end
    
    def get_completion_json(prompt, max_tokens = 1500)
      # Switch a mock si está configurado
      if ENV['MOCK_OPENAI'] == 'true'
        return MockOpenaiService.get_completion_json(prompt, max_tokens)
      end

      client = OpenAI::Client.new

      response = client.chat(
        parameters: {
          model: COMPLETION_MODEL,
          messages: [
            { role: "system", content: "You are an expert in electronic components classification and analysis. You provide detailed analysis followed by structured JSON decisions." },
            { role: "user", content: prompt }
          ],
          max_tokens: max_tokens,
          temperature: 0.1  # Low temperature for consistent analysis
        }
      )

      content = response.dig("choices", 0, "message", "content")

      begin
        # Extraer JSON del bloque de código markdown
        json_match = content.match(/```json\s*(\{.*?\})\s*```/m)
        if json_match
          JSON.parse(json_match[1])
        else
          # Fallback: buscar JSON al final del texto
          json_start = content.rindex('{')
          json_end = content.rindex('}')
          if json_start && json_end && json_end > json_start
            JSON.parse(content[json_start..json_end])
          else
            raise JSON::ParserError, "No JSON found in response"
          end
        end
      rescue JSON::ParserError => e
        Rails.logger.error("Error parsing JSON response: #{e.message}")
        Rails.logger.error("Full response: #{content}")
        {
          "should_correct" => false,
          "confidence_level" => "low",
          "current_assignment_correct" => true,
          "recommended_commodity" => nil,
          "recommended_scope" => nil,
          "reasoning" => "Error parsing AI response",
          "evidence" => "JSON parse error: #{e.message}"
        }
      end
    rescue => e
      Rails.logger.error("OpenAI completion JSON error: #{e.message}")
      {
        "should_correct" => false,
        "confidence_level" => "low",
        "current_assignment_correct" => true,
        "recommended_commodity" => nil,
        "recommended_scope" => nil,
        "reasoning" => "API error occurred",
        "evidence" => "Error: #{e.message}"
      }
    end

    # Invalidar embedding específico del cache cuando se modifica
    def invalidate_embedding_cache(text)
      sanitized_text = sanitize_text_for_embedding(text)
      if @@embeddings_cache.key?(sanitized_text)
        @@embeddings_cache.delete(sanitized_text)
        Rails.logger.info "🗑️ [EMBEDDINGS CACHE] Invalidated cache for: #{sanitized_text[0..30]}..."
        true
      else
        false
      end
    end

    # Invalidar múltiples embeddings del cache
    def invalidate_embeddings_cache(texts)
      invalidated_count = 0
      texts.each do |text|
        invalidated_count += 1 if invalidate_embedding_cache(text)
      end

      if invalidated_count > 0
        Rails.logger.info "🗑️ [EMBEDDINGS CACHE] Invalidated #{invalidated_count} cached embeddings"
      end

      invalidated_count
    end

    # Obtener estadísticas del cache de embeddings
    def embeddings_cache_stats
      {
        size: @@embeddings_cache.size,
        keys: @@embeddings_cache.keys.first(5),  # Primeras 5 claves como muestra
        memory_mb: (@@embeddings_cache.to_s.bytesize / 1024.0 / 1024.0).round(2)
      }
    end

    private
    
    # Buscar embedding existente en base de datos (individual - para compatibilidad)
    def find_embedding_in_db(text)
      ProcessedItem.where("description = ? AND embedding IS NOT NULL", text).first&.embedding
    end
    
    # Buscar embeddings existentes en base de datos (batch optimizado)
    def preload_embeddings_from_db_batched(texts)
      sanitized_texts = texts.map { |text| sanitize_text_for_embedding(text) }.uniq
      db_embeddings_cache = {}
      
      Rails.logger.info "💾 [BD CACHE] Loading embeddings for #{sanitized_texts.size} unique texts in batches"
      
      # Procesar en lotes para evitar queries muy grandes
      sanitized_texts.each_slice(ExcelProcessorConfig::BATCH_SIZE).with_index do |batch_texts, batch_index|
        Rails.logger.info "💾 [BD CACHE] Processing batch #{batch_index + 1} (#{batch_texts.size} texts)"
        
        # Buscar por el texto completo del embedding, no solo description
        batch_results = {}
        ProcessedItem.where.not(embedding: nil).find_each do |item|
          item_embedding_text = item.recreate_embedding_text
          if batch_texts.include?(item_embedding_text)
            batch_results[item_embedding_text] = item.embedding
            Rails.logger.debug "💾 [BD CACHE] Found existing embedding for: #{item_embedding_text[0..50]}..."
          end
        end
        
        db_embeddings_cache.merge!(batch_results)
      end
      
      Rails.logger.info "💾 [BD CACHE] Loaded #{db_embeddings_cache.size} existing embeddings from database"
      db_embeddings_cache
    end
    
    # Sanitizar texto para embedding (helper method)
    def sanitize_text_for_embedding(text)
      text.to_s.strip
    end
    
    # Estimar tokens para text-embedding-3-small (aprox 1 token = 4 caracteres)
    def estimate_tokens(text)
      (text.to_s.length / 4.0).ceil
    end
    
    # Verificar rate limit y esperar si es necesario para proteger embeddings
    def check_and_wait_if_needed(estimated_tokens)
      current_minute = Time.current.beginning_of_minute

      # Reset contador si cambió el minuto
      if current_minute > @@minute_start
        @@tokens_per_minute = 0
        @@minute_start = current_minute
      end

      # Si excedería el límite, esperar hasta el próximo minuto
      if @@tokens_per_minute + estimated_tokens > TOKEN_LIMIT_PER_MINUTE
        sleep_time = 60 - Time.current.sec + 1 # +1 para estar seguro
        Rails.logger.warn "⏳ [RATE LIMIT] Se alcanzó el límite de #{TOKEN_LIMIT_PER_MINUTE} tokens/min. Esperando #{sleep_time}s para proteger embeddings..."
        sleep(sleep_time)
        @@tokens_per_minute = 0
        @@minute_start = Time.current.beginning_of_minute
      end

      # Actualizar contador
      @@tokens_per_minute += estimated_tokens
      
      # Log ocasional para monitoreo
      if @@tokens_per_minute % 50_000 < estimated_tokens
        Rails.logger.info "📊 [RATE LIMIT] Tokens usados en este minuto: #{@@tokens_per_minute}/#{TOKEN_LIMIT_PER_MINUTE}"
      end
    end
  end
end