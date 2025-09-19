# frozen_string_literal: true

module CommodityAnalysis
  class DataFormatter
    include SimilarityCalculable
    
    class << self
      include SimilarityCalculable
      
      def format_analysis_response(item, ai_analysis, similares_data)
        {
          item_id: item.id,
          item_description: item.description,
          item_manufacturer: item.global_mfg_name,
          item_mpn: item.mfg_partno,
          current_commodity: item.commodity,
          current_scope: item.scope,
          original_embedding_text: item.recreate_embedding_text,
          top_5_similares: similares_data,
          ai_analysis: ai_analysis,
          success: true,
          generated_at: Time.current
        }
      end
      
      def get_similar_commodities_data(item)
        return [] unless item.embedding.present?

        similares = CommodityReference.find_most_similar(item.embedding, ExcelProcessorConfig::SIMILARITY_ANALYSIS_LIMIT)

        start_time = Time.current

        result = similares.map.with_index do |commodity, index|
          # Usar la similitud ya calculada por PostgreSQL en lugar de recalcular
          similarity = commodity.attributes['cosine_similarity'] || commodity.cosine_similarity || 0.0

          {
            posicion: index + 1,
            nombre: commodity.level3_desc,
            similitud_porcentaje: (similarity * 100).round(2),
            scope: commodity.infinex_scope_status,
            categoria: [commodity.level1_desc, commodity.level2_desc].compact.join(' > '),
            texto_embedding: commodity.full_text_for_embedding,
            keywords: commodity.keyword,
            manufacturers: commodity.mfr,
            typical_mpns: commodity.typical_mpn_by_manufacturer
          }
        end
        
        elapsed_ms = ((Time.current - start_time) * 1000).round(2)
        Rails.logger.info "⏱️ [TIMING] Similar commodities data formatting: #{similares.size} items formatted in #{elapsed_ms}ms (using precomputed PostgreSQL cosine similarities)" if elapsed_ms > 1
        
        result
      end
    end
  end
end