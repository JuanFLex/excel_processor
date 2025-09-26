require 'set'

class TopEarAnalyzerJob < ApplicationJob
  queue_as :default
  
  discard_on StandardError do |job, error|
    Rails.logger.error("Error in TopEarAnalyzerJob: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n"))
  end
  
  def perform(processed_file_id)
    start_time = Time.current
    processed_file = ProcessedFile.find(processed_file_id)
    
    Rails.logger.info "🤖 [AUTO-AI] Starting automatic analysis for top #{ExcelProcessorConfig::TOP_EAR_ANALYSIS_COUNT} EAR items in file: #{processed_file.original_filename}"
    
    # Obtener los top items con mayor EAR (calculado como EAU × precio_mínimo)
    top_items = processed_file.processed_items
                              .where.not(eau: nil)
                              .where('eau > 0')
                              .where('std_cost > 0 OR last_purchase_price > 0 OR last_po > 0')
                              .order(Arel.sql('eau * LEAST(
                                NULLIF(CASE WHEN std_cost > 0 THEN std_cost END, NULL),
                                NULLIF(CASE WHEN last_purchase_price > 0 THEN last_purchase_price END, NULL),
                                NULLIF(CASE WHEN last_po > 0 THEN last_po END, NULL)
                              ) DESC'))
                              .limit(ExcelProcessorConfig::TOP_EAR_ANALYSIS_COUNT)
    
    if top_items.empty?
      Rails.logger.info "🤖 [AUTO-AI] No items found with EAR values for analysis"
      return
    end
    
    Rails.logger.info "🤖 [AUTO-AI] Found #{top_items.count} items for analysis"
    
    results = []
    
    top_items.each do |item|
      Rails.logger.info "🤖 [AUTO-AI] Analyzing item #{item.id} (EAR: #{item.ear_value})"
      
      begin
        item_start_time = Time.current
        result = CommodityAnalysisService.analyze_for_auto_correction(item.id)
        item_time_ms = ((Time.current - item_start_time) * 1000).round(2)
        result[:analysis_time_ms] = item_time_ms
        results << result
        
        if result[:correction_applied]
          Rails.logger.info "✅ [AUTO-AI] Correction applied to item #{item.id}: #{result[:old_commodity]} -> #{result[:new_commodity]} (#{item_time_ms}ms)"
        else
          Rails.logger.info "ℹ️ [AUTO-AI] No correction needed for item #{item.id} (#{item_time_ms}ms)"
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
    
    # Log performance summary
    total_time_ms = ((Time.current - start_time) * 1000).round(2)
    corrections_count = results.count { |r| r[:correction_applied] }
    avg_time_per_item = results.any? ? (results.sum { |r| r[:analysis_time_ms] || 0 } / results.count).round(2) : 0

    Rails.logger.info "🎯 [AUTO-AI] Analysis complete. #{corrections_count}/#{results.count} items corrected"
    Rails.logger.info "⏱️ [TIMING] Total Top EAR Analysis: #{total_time_ms}ms"
    Rails.logger.info "⏱️ [TIMING] Average per item: #{avg_time_per_item}ms"

    if results.any?
      slowest_item = results.max_by { |r| r[:analysis_time_ms] || 0 }
      Rails.logger.info "🐌 [BOTTLENECK] Slowest item analysis: #{slowest_item[:analysis_time_ms]}ms"
    end

    # Regenerate Excel file if any corrections were applied
    if corrections_count > 0
      Rails.logger.info "🔄 [AUTO-AI] Regenerating Excel file due to #{corrections_count} corrections"
      regenerate_excel_file(processed_file)
    end

    results
  end

  private

  def regenerate_excel_file(processed_file)
    start_time = Time.current

    begin
      # Delete old Excel file if it exists
      if processed_file.result_file_path.present? && File.exist?(processed_file.result_file_path)
        File.delete(processed_file.result_file_path)
        Rails.logger.info "🗑️ [AUTO-AI] Deleted old Excel file: #{processed_file.result_file_path}"
      end

      # Use the same logic as export_filtered but for all items
      file_path = generate_excel_from_items(processed_file)
      processed_file.update(result_file_path: file_path)

      generation_time_ms = ((Time.current - start_time) * 1000).round(2)
      Rails.logger.info "✅ [AUTO-AI] Excel file regenerated successfully (#{generation_time_ms}ms)"

    rescue => e
      Rails.logger.error "❌ [AUTO-AI] Error regenerating Excel file: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def generate_excel_from_items(processed_file)
    Rails.logger.info "🔄 [AUTO-AI] Regenerating Excel file with AI corrections..."
    
    # Use centralized Excel generation service
    excel_generator = ExcelGeneratorService.new(processed_file)
    file_path = excel_generator.generate_excel_file
    
    Rails.logger.info "✅ [AUTO-AI] Excel file regenerated: #{file_path}"
    file_path
  end

  # Load SQL caches for Excel regeneration (same logic as ExcelProcessorService)
  def load_sql_caches_for_regeneration(processed_file, items)
    # Return mock data if using mock SQL server
    if ENV['MOCK_SQL_SERVER'] == 'true'
      return {
        total_demand: {},
        min_price: {},
        cross_ref: {}
      }
    end

    caches = {
      total_demand: {},
      min_price: {},
      cross_ref: {}
    }

    # Extract unique items and MPNs
    unique_items = items.map { |item| item.item.to_s.strip }.compact.uniq
    unique_mpns = items.map { |item| item.mfg_partno.to_s.strip }.compact.uniq.reject(&:empty?)

    Rails.logger.info "🔄 [REGEN] Loading SQL caches for #{unique_items.size} unique items and #{unique_mpns.size} unique MPNs"

    begin
      # Load Total Demand cache (only if enabled for this file)
      if processed_file.enable_total_demand_lookup && unique_items.any?
        unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_items|
          quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')

          result = ItemLookup.connection.select_all(
            "SELECT ITEM, TOTAL_DEMAND
             FROM ExcelProcessorAMLfind
             WHERE ITEM IN (#{quoted_items}) AND TOTAL_DEMAND IS NOT NULL"
          )

          result.rows.each do |row|
            caches[:total_demand][row[0]] = row[1]
          end
        end
        Rails.logger.info "🔄 [REGEN] Loaded #{caches[:total_demand].size} Total Demand entries"
      end

      # Load Min Price cache
      if unique_items.any?
        unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_items|
          quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')

          result = ItemLookup.connection.select_all(
            "SELECT ITEM, MIN_PRICE
             FROM ExcelProcessorAMLfind
             WHERE ITEM IN (#{quoted_items}) AND MIN_PRICE IS NOT NULL"
          )

          result.rows.each do |row|
            caches[:min_price][row[0]] = row[1]
          end
        end
        Rails.logger.info "🔄 [REGEN] Loaded #{caches[:min_price].size} Min Price entries"
      end

      # Load Cross Reference cache
      if unique_mpns.any?
        # Apply component grade filter based on processed file configuration
        include_medical_auto = processed_file&.include_medical_auto_grades || false
        grade_filter = include_medical_auto ? "AND COMPONENT_GRADE = 'AUTO'" : "AND COMPONENT_GRADE = 'COMMERCIAL'"


        unique_mpns.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_mpns|
          quoted_mpns = batch_mpns.map { |mpn| "'#{mpn.gsub("'", "''")}'" }.join(',')

          result = ItemLookup.connection.select_all(
            "SELECT CROSS_REF_MPN, INFINEX_MPN
             FROM INX_dataLabCrosses
             WHERE CROSS_REF_MPN IN (#{quoted_mpns}) AND INFINEX_MPN IS NOT NULL
             #{grade_filter}"
          )

          result.rows.each do |row|
            caches[:cross_ref][row[0]] = row[1]
          end
        end
        Rails.logger.info "🔄 [REGEN] Loaded #{caches[:cross_ref].size} Cross Reference entries"
      end

    rescue => e
      Rails.logger.error "❌ [REGEN] Error loading SQL caches: #{e.message}"
      # Return empty caches so regeneration continues without SQL data
    end

    caches
  end
end