class TopEarAnalyzerJob < ApplicationJob
  queue_as :default
  
  discard_on StandardError do |job, error|
    Rails.logger.error("Error in TopEarAnalyzerJob: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n"))
  end
  
  def perform(processed_file_id)
    processed_file = ProcessedFile.find(processed_file_id)
    
    Rails.logger.info "🤖 [AUTO-AI] Starting automatic analysis for top #{ExcelProcessorConfig::TOP_EAR_ANALYSIS_COUNT} EAR items in file: #{processed_file.original_filename}"
    
    # Obtener los top items con mayor EAR
    top_items = processed_file.processed_items
                              .where.not(ear: nil)
                              .where('ear > 0')
                              .order(ear: :desc)
                              .limit(ExcelProcessorConfig::TOP_EAR_ANALYSIS_COUNT)
    
    if top_items.empty?
      Rails.logger.info "🤖 [AUTO-AI] No items found with EAR values for analysis"
      return
    end
    
    Rails.logger.info "🤖 [AUTO-AI] Found #{top_items.count} items for analysis"
    
    results = []
    
    top_items.each do |item|
      Rails.logger.info "🤖 [AUTO-AI] Analyzing item #{item.id} (EAR: #{item.ear})"
      
      begin
        result = CommodityAnalysisService.analyze_for_auto_correction(item.id)
        results << result
        
        if result[:correction_applied]
          Rails.logger.info "✅ [AUTO-AI] Correction applied to item #{item.id}: #{result[:old_commodity]} -> #{result[:new_commodity]}"
        else
          Rails.logger.info "ℹ️ [AUTO-AI] No correction needed for item #{item.id}"
        end
        
      rescue => e
        Rails.logger.error "❌ [AUTO-AI] Error analyzing item #{item.id}: #{e.message}"
        results << {
          item_id: item.id,
          error: e.message,
          success: false,
          correction_applied: false
        }
      end
    end
    
    # Log summary
    corrections_count = results.count { |r| r[:correction_applied] }
    Rails.logger.info "🎯 [AUTO-AI] Analysis complete. #{corrections_count}/#{results.count} items corrected"
    
    results
  end
end