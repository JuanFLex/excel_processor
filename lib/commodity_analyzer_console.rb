# frozen_string_literal: true

# Commodity Analyzer Console Helper
# Comandos útiles para analizar commodities en Rails Console

class CommodityAnalyzerConsole
  extend SimilarityCalculable::ClassMethods
  
  class << self
    def help
      puts <<~HELP
        🔍 COMMODITY ANALYZER - Comandos Disponibles:
        ================================================
        
        # Análisis individual
        CommodityAnalyzerConsole.analyze(item_id)        # Análisis completo con IA
        CommodityAnalyzerConsole.compare_embeddings(item_id)  # Solo comparación de embeddings
        
        # Ejemplos:
        CommodityAnalyzerConsole.analyze(484244)
        CommodityAnalyzerConsole.compare_embeddings(484244)
      HELP
    end
    
    def analyze(item_id)
      puts "🔍 Analyzing ProcessedItem #{item_id}..."
      puts "=" * 60
      
      result = CommodityAnalysisService.analyze_commodity_assignment(item_id)
      
      if result[:success]
        print_detailed_analysis(result)
      else
        puts "❌ Error: #{result[:error]}"
      end
      
      nil
    rescue StandardError => e
      puts "❌ Error analyzing item #{item_id}: #{e.message}"
      nil
    end
    
    def compare_embeddings(item_id)
      puts "🔍 Embedding Comparison for ProcessedItem #{item_id}"
      puts "=" * 60
      
      item = ProcessedItem.find(item_id)
      
      puts "🔤 ORIGINAL EMBEDDING TEXT (ProcessedItem):"
      puts item.recreate_embedding_text
      puts
      puts "Current Assignment: #{item.commodity} (#{item.scope})"
      puts
      
      if item.embedding.present?
        similares = CommodityReference.find_most_similar(item.embedding, 5)
        
        puts "🎯 TOP 5 SIMILAR COMMODITIES & THEIR EMBEDDING TEXTS:"
        puts
        
        similares.each_with_index do |commodity, index|
          # Usar la similitud ya calculada por PostgreSQL en lugar de recalcular
          similarity = commodity.attributes['cosine_similarity'] || commodity.cosine_similarity || 0.0
          
          puts "#{index + 1}. #{commodity.level3_desc} (#{(similarity * 100).round(2)}%)"
          puts "   Scope: #{commodity.infinex_scope_status}"
          puts "   Category: #{[commodity.level1_desc, commodity.level2_desc].compact.join(' > ')}"
          puts
          puts "   📝 Reference embedding text:"
          puts "   #{commodity.full_text_for_embedding.gsub("\n", "\n   ")}"
          puts "=" * 60
        end
      else
        puts "❌ No embedding found for this item"
      end
      
      nil
    rescue StandardError => e
      puts "❌ Error: #{e.message}"
      nil
    end
    
    private
    
    def print_detailed_analysis(result)
      puts "📋 COMPONENT DETAILS:"
      puts "Description: #{result[:item_description]}"
      puts "Manufacturer: #{result[:item_manufacturer]}"
      puts "MPN: #{result[:item_mpn]}"
      puts "Current Commodity: #{result[:current_commodity]}"
      puts "Current Scope: #{result[:current_scope]}"
      puts
      
      puts "🔤 ORIGINAL EMBEDDING TEXT (ProcessedItem):"
      puts result[:original_embedding_text]
      puts
      
      puts "🎯 TOP 5 SIMILAR COMMODITIES:"
      result[:top_5_similares].each do |sim|
        puts "#{sim[:posicion]}. #{sim[:nombre]} (#{sim[:similitud_porcentaje]}%)"
        puts "   Scope: #{sim[:scope]} | Category: #{sim[:categoria]}"
        puts "   Keywords: #{sim[:keywords] || 'None'}"
        puts
        puts "   📝 Embedding text of this commodity reference:"
        puts "   #{sim[:texto_embedding].gsub("\n", "\n   ")}"
        puts "-" * 50
      end
      
      puts "🤖 AI ANALYSIS:"
      puts result[:ai_analysis]
      puts
      puts "⏰ Generated at: #{result[:generated_at]}"
    end
    
  end
end

# Auto-load en Rails console
if defined?(Rails::Console)
  puts "🔍 Commodity Analyzer loaded!"
  puts "Type: CommodityAnalyzerConsole.help"
end