class MockOpenaiService
  # Mock service que imita OpenaiService para desarrollo sin acceso a OpenAI
  
  class << self
    def get_embeddings(texts)
      return [] if texts.empty?
      
      Rails.logger.info "🎭 [MOCK OPENAI] Generating fake embeddings for #{texts.size} texts..."
      
      # Generar embeddings falsos pero realistas (1536 dimensiones)
      texts.map do |text|
        # Generar embedding determinístico basado en el texto para consistencia
        seed = text.to_s.bytes.sum
        Random.srand(seed)
        
        embedding = Array.new(1536) { Random.rand(-1.0..1.0) }
        
        Rails.logger.debug "🎭 [MOCK OPENAI] Generated fake embedding for: #{text[0..30]}..."
        embedding
      end
    end
    
    def identify_columns(sample_rows, target_columns)
      Rails.logger.info "🎭 [MOCK OPENAI] Identifying columns with mock logic..."
      
      # Mock column mapping inteligente basado en nombres comunes
      headers = sample_rows.first&.keys || []
      mapping = {}
      
      target_columns.each do |target|
        # Buscar columnas similares
        match = headers.find do |header|
          case target
          when 'ITEM'
            header.to_s.upcase.include?('ITEM')
          when 'DESCRIPTION' 
            header.to_s.upcase.include?('DESC')
          when 'MFG_PARTNO'
            header.to_s.upcase.include?('PART') || header.to_s.upcase.include?('MFG')
          when 'GLOBAL_MFG_NAME'
            header.to_s.upcase.include?('MFG') || header.to_s.upcase.include?('MANUF')
          when 'STD_COST'
            header.to_s.upcase.include?('COST') || header.to_s.upcase.include?('PRICE')
          when 'LAST_PURCHASE_PRICE'
            header.to_s.upcase.include?('PURCHASE') || header.to_s.upcase.include?('PRICE')
          when 'LAST_PO'
            header.to_s.upcase.include?('PO') || header.to_s.upcase.include?('ORDER')
          when 'EAU'
            header.to_s.upcase.include?('EAU') || header.to_s.upcase.include?('USAGE')
          when 'SITE'
            header.to_s.upcase.include?('SITE') || header.to_s.upcase.include?('LOCATION')
          when 'SFDC QUOTE NUMBER'
            header.to_s.upcase.include?('SFDC') || header.to_s.upcase.include?('QUOTE') || header.to_s.upcase.include?('ID')
          when 'LEVEL3_DESC'
            header.to_s.upcase.include?('LEVEL3') || header.to_s.upcase.include?('L3')
          else
            false
          end
        end
        
        mapping[target] = match
      end
      
      Rails.logger.info "🎭 [MOCK OPENAI] Column mapping: #{mapping}"
      mapping
    end
    
    def get_embedding_for_text(text)
      embeddings = get_embeddings([text])
      embeddings.first
    end
    
    def get_completion(prompt, max_tokens = 1500)
      Rails.logger.info "🎭 [MOCK OPENAI] Generating mock completion..."
      
      # Mock analysis basado en patrones comunes
      if prompt.include?('analyze') && prompt.include?('commodity')
        return generate_mock_commodity_analysis(prompt)
      end
      
      "🎭 MOCK ANALYSIS: This is a simulated response. In production, this would contain AI-generated analysis based on the provided data."
    end
    
    private
    
    def generate_mock_commodity_analysis(prompt)
      <<~ANALYSIS
        ## MOCK COMMODITY ANALYSIS REPORT

        **Current Assignment Analysis:**
        Based on the component details, the current commodity assignment appears to be reasonable but could potentially be optimized.

        **Key Observations:**
        1. **Package Size Indicators**: The MPN suggests a specific package size (e.g., 0805, 0402, 1206)
        2. **Component Type**: Clear indicators in the description point to the component family
        3. **Manufacturer Match**: The manufacturer is recognized and matches typical suppliers for this commodity

        **Recommendations:**
        1. **Keyword Enhancement**: Consider adding package size keywords (e.g., "0805", "1206") to improve matching precision
        2. **MPN Pattern Analysis**: The part number pattern suggests this component would benefit from more specific classification
        3. **Similarity Score**: Current similarity could be improved by enhancing reference commodity descriptions

        **Suggested Actions:**
        - Add relevant keywords to the top-matching commodity reference
        - Review similar components for pattern consistency
        - Consider creating more specific commodity subcategories if needed

        *Note: This is a mock analysis for development. Production version would provide detailed AI-powered insights.*
      ANALYSIS
    end
  end
end