# frozen_string_literal: true

class CommodityAnalysisService
  class << self
    def analyze_commodity_assignment(processed_item_id)
      item = ProcessedItem.find(processed_item_id)
      
      # 1. Obtener datos básicos
      texto_original = item.recreate_embedding_text
      current_commodity = item.commodity
      current_scope = item.scope
      
      # 2. Obtener top 5 commodities similares con sus datos
      similares_data = CommodityAnalysis::DataFormatter.get_similar_commodities_data(item)
      
      # 3. Construir prompt estructurado para IA
      prompt = build_analysis_prompt({
        item_id: item.id,
        item_description: item.description,
        item_manufacturer: item.global_mfg_name,
        item_mpn: item.mfg_partno,
        texto_original: texto_original,
        commodity_asignado: current_commodity,
        scope_asignado: current_scope,
        similares: similares_data
      })
      
      # 4. Obtener análisis de IA
      analysis = OpenaiService.get_completion(prompt, 2000)
      
      # 5. Formatear respuesta
      CommodityAnalysis::DataFormatter.format_analysis_response(item, analysis, similares_data)
    end
    
    def analyze_multiple_items(processed_item_ids)
      results = []
      
      processed_item_ids.each do |item_id|
        results << analyze_commodity_assignment(item_id)
      rescue StandardError => e
        Rails.logger.error "Error analyzing item #{item_id}: #{e.message}"
        results << {
          item_id: item_id,
          error: e.message,
          success: false
        }
      end
      
      results
    end
    
    def analyze_for_auto_correction(processed_item_id)
      item = ProcessedItem.find(processed_item_id)
      
      # Obtener datos básicos y similares (mismo proceso que análisis manual)
      texto_original = item.recreate_embedding_text
      current_commodity = item.commodity
      current_scope = item.scope
      similares_data = CommodityAnalysis::DataFormatter.get_similar_commodities_data(item)
      
      # Construir prompt para corrección automática (detallado pero con respuesta JSON)
      prompt = build_auto_correction_prompt({
        item_id: item.id,
        item_description: item.description,
        item_manufacturer: item.global_mfg_name,
        item_mpn: item.mfg_partno,
        texto_original: texto_original,
        commodity_asignado: current_commodity,
        scope_asignado: current_scope,
        similares: similares_data
      })
      
      # Obtener análisis estructurado de IA
      analysis = OpenaiService.get_completion_json(prompt, 1500)
      
      # Procesar respuesta y aplicar corrección si es recomendada
      process_auto_correction(item, analysis)
    rescue StandardError => e
      Rails.logger.error "Error in auto-correction for item #{processed_item_id}: #{e.message}"
      {
        item_id: processed_item_id,
        error: e.message,
        success: false,
        correction_applied: false
      }
    end
    
    private
    
    def build_analysis_prompt(data)
      <<~PROMPT
        Eres un experto en clasificación de componentes electrónicos y análisis de commodities. 
        
        Analiza la asignación de commodity para este componente y proporciona recomendaciones detalladas.

        ## INFORMACIÓN DEL COMPONENTE
        **ID:** #{data[:item_id]}
        **Descripción:** #{data[:item_description]}
        **Fabricante:** #{data[:item_manufacturer]}
        **MPN:** #{data[:item_mpn]}
        **Commodity Actual:** #{data[:commodity_asignado]}
        **Scope Actual:** #{data[:scope_asignado]}
        
        **Texto de Embedding Utilizado:**
        #{data[:texto_original]}
        
        ## TOP #{ExcelProcessorConfig::SIMILARITY_ANALYSIS_LIMIT} COMMODITIES SIMILARES
        #{format_similares_for_prompt(data[:similares])}
        
        ## SOLICITUD DE ANÁLISIS
        Proporciona un análisis completo que incluya:
        
        1. **Evaluación de la asignación actual**: ¿Es correcta? ¿Por qué?
        2. **Análisis de coincidencias**: ¿Qué elementos del MPN, descripción o fabricante apoyan la asignación?
        3. **Recomendaciones específicas**: 
           - ¿Mantener o cambiar la asignación?
           - ¿Qué keywords añadir a las referencias?
           - ¿Cómo mejorar el matching?
        4. **Nivel de confianza**: Alto/Medio/Bajo con justificación

        Sé específico y técnico en tus recomendaciones.
      PROMPT
    end
    
    def format_similares_for_prompt(similares)
      similares.map do |sim|
        <<~SIMILAR
          **#{sim[:posicion]}. #{sim[:nombre]} (#{sim[:similitud_porcentaje]}% similarity)**
          - Scope: #{sim[:scope]}
          - Category: #{sim[:categoria]}
          - Keywords: #{sim[:keywords] || 'None'}
          - Typical Manufacturers: #{sim[:manufacturers] || 'None'}
          - Sample MPNs: #{sim[:typical_mpns]&.split(',')&.first(3)&.join(', ') || 'None'}
          
          Embedding Text:
          #{sim[:texto_embedding].gsub("\n", " | ")}
          
        SIMILAR
      end.join("\n")
    end
    
    def build_auto_correction_prompt(data)
      <<~PROMPT
        Eres un experto en clasificación de componentes electrónicos y análisis de commodities.
        
        Analiza la asignación de commodity para este componente y determina si necesita corrección automática.
        
        ## INFORMACIÓN DEL COMPONENTE
        **ID:** #{data[:item_id]}
        **Descripción:** #{data[:item_description]}
        **Fabricante:** #{data[:item_manufacturer]}
        **MPN:** #{data[:item_mpn]}
        **Commodity Actual:** #{data[:commodity_asignado]}
        **Scope Actual:** #{data[:scope_asignado]}
        
        **Texto de Embedding Utilizado:**
        #{data[:texto_original]}
        
        ## TOP #{ExcelProcessorConfig::SIMILARITY_ANALYSIS_LIMIT} COMMODITIES SIMILARES
        #{format_similares_for_prompt(data[:similares])}
        
        ## INSTRUCCIONES PARA RESPUESTA JSON
        
        Analiza si la asignación actual es correcta o necesita cambio. SOLO recomienda cambio si:
        1. Hay evidencia clara de error en la asignación actual
        2. Existe un commodity similar que sea claramente mejor basado en MPN, descripción y fabricante
        3. El MPN o descripción claramente indica otro tipo de componente
        
        Responde ÚNICAMENTE en formato JSON válido:
        
        {
          "should_correct": boolean,
          "confidence_level": "high|medium|low",
          "current_assignment_correct": boolean,
          "recommended_commodity": "nombre_commodity",
          "recommended_scope": "scope_name",
          "reasoning": "explicación breve y técnica de la decisión",
          "evidence": "elementos específicos del MPN/descripción que apoyan la decisión"
        }
        
        Si should_correct es false, deja recommended_commodity y recommended_scope como null.
        Sé conservador: solo recomienda cambios cuando estés muy seguro.
      PROMPT
    end
    
    def process_auto_correction(item, analysis)
      result = {
        item_id: item.id,
        success: true,
        correction_applied: false,
        analysis: analysis
      }
      
      return result unless analysis['should_correct'] && analysis['confidence_level'] == 'high'
      
      # Aplicar corrección solo con confianza alta
      old_commodity = item.commodity
      old_scope = item.scope
      
      item.update!(
        commodity: analysis['recommended_commodity'],
        scope: analysis['recommended_scope']
      )
      
      Rails.logger.info "Auto-corrected item #{item.id}: #{old_commodity} -> #{analysis['recommended_commodity']}"
      
      result[:correction_applied] = true
      result[:old_commodity] = old_commodity
      result[:old_scope] = old_scope
      result[:new_commodity] = analysis['recommended_commodity']
      result[:new_scope] = analysis['recommended_scope']
      
      result
    end
  end
end