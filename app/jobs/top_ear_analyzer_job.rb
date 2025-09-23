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
    temp_file_path = Rails.root.join('storage', "processed_#{processed_file.id}_#{Time.current.to_i}.xlsx")

    items = processed_file.processed_items.to_a

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Processed Items") do |sheet|
      # Same headers as original
      headers = [
        'SFDC_QUOTE_NUMBER', 'ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME',
        'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE',
        'LAST_PO', 'EAU', 'Commodity', 'Scope', 'Part Duplication Flag',
        'Potential Coreworks Cross', 'EAR', 'EAR Threshold Status',
        'Previously Quoted', 'Quote Date', 'Previous SFDC Quote Number',
        'Previously Quoted INX_MPN', 'Total Demand', 'Min Price'
      ]

      # Define styles matching original Excel format
      header_style = workbook.styles.add_style(
        bg_color: "FA4616",  # Orange for quote form columns
        fg_color: "FFFFFF",
        b: true,
        alignment: { horizontal: :center },
        font_name: "Century Gothic",
        sz: 11
      )

      auxiliary_style = workbook.styles.add_style(
        bg_color: "5498c6",  # Blue for auxiliary columns
        fg_color: "FFFFFF",
        b: true,
        alignment: { horizontal: :center },
        font_name: "Century Gothic",
        sz: 11
      )

      # Define which columns are from Quote form (use ORANGE)
      quote_form_columns = ['ITEM', 'MFG_PARTNO', 'GLOBAL_MFG_NAME', 'DESCRIPTION', 'SITE', 'STD_COST', 'LAST_PURCHASE_PRICE', 'LAST_PO', 'EAU', 'Commodity']

      # Create array of styles based on column name
      header_styles = headers.map do |header|
        quote_form_columns.include?(header) ? header_style : auxiliary_style
      end

      # Add header with column-specific styling
      sheet.add_row headers, style: header_styles

      # Add data (simplified without SQL lookups for regeneration speed)
      item_tracker = Set.new
      items.each do |item|
        # Track unique items (same logic as main generation)
        unique_flg = item_tracker.include?(item.item) ? 'AML' : 'Unique'
        item_tracker.add(item.item)

        sheet.add_row [
          item.sugar_id, item.item, item.mfg_partno, item.global_mfg_name,
          item.description, item.site, item.std_cost, item.last_purchase_price,
          item.last_po, item.eau, item.commodity, item.scope, unique_flg,
          '', item.ear_value, item.ear_threshold_status,
          'NO', '', '', '',
          '', ''
        ]
      end
    end

    package.serialize(temp_file_path)
    temp_file_path.to_s
  end
end