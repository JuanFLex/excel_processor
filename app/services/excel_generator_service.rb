# app/services/excel_generator_service.rb
require 'set'

class ExcelGeneratorService
  def initialize(processed_file)
    @processed_file = processed_file
    @proposal_quotes_cache = {}
    @cross_references_cache = {}
    @aml_total_demand_cache = {}
    @aml_min_price_cache = {}
  end

  def generate_excel_file(items = nil)
    Rails.logger.info "🚀 [EXCEL GENERATOR] Starting Excel generation for file: #{@processed_file.original_filename}"
    start_time = Time.current

    # Cargar todos los caches necesarios
    load_all_caches(items)

    # Crear el archivo Excel
    file_path = create_excel_file(items)

    generation_time_ms = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
    Rails.logger.info "✅ [EXCEL GENERATOR] Excel file generated successfully in #{generation_time_ms}ms"

    file_path
  end

  private

  def load_all_caches(items = nil)
    # Usar items proporcionados o cargar todos del archivo
    processed_items = items || @processed_file.processed_items.to_a

    # Extraer valores únicos para optimizar queries
    unique_items = processed_items.map(&:item).compact.uniq
    unique_mpns = processed_items.map(&:mfg_partno).compact.uniq.reject(&:empty?)

    Rails.logger.info "📊 [EXCEL GENERATOR] Loading caches for #{unique_items.size} unique items and #{unique_mpns.size} unique MPNs"

    # Cargar todos los caches en paralelo
    load_proposal_quotes_cache(unique_items)
    load_cross_references_cache_for_mpns(unique_mpns)
    load_aml_caches(unique_items)
  end

  def create_excel_file(items = nil)
    # Usar items proporcionados o cargar todos del archivo
    processed_items = items || @processed_file.processed_items.to_a

    # Crear el paquete Excel
    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Processed Items") do |sheet|
      # Definir headers - Expandir TARGET_COLUMNS con columnas auxiliares
      headers = ExcelProcessorConfig::TARGET_COLUMNS + [
        'Commodity', 'Scope', 'Part Duplication Flag',
        'Potential Coreworks Cross', 'EAR', 'EAR Threshold Status',
        'Previously Quoted', 'Quote Date', 'Previous SFDC Quote Number',
        'Previously Quoted INX_MPN', 'Total Demand', 'Min Price'
      ]

      # Estilos para headers
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

      # Estilos para datos
      currency_style = workbook.styles.add_style(
        format_code: '$#,##0.00',
        font_name: "Century Gothic",
        sz: 11
      )

      thousands_style = workbook.styles.add_style(
        format_code: '#,##0',
        font_name: "Century Gothic",
        sz: 11
      )

      ear_fallback_style = workbook.styles.add_style(
        format_code: '$#,##0.00',
        font_name: "Century Gothic",
        sz: 11,
        bg_color: "FFFF99"  # Yellow for fallback values
      )

      # Definir qué columnas son del Quote form (TARGET_COLUMNS + Commodity)
      quote_form_columns = ExcelProcessorConfig::TARGET_COLUMNS + ['Commodity']

      # Aplicar estilos a headers
      header_styles = headers.map do |header|
        quote_form_columns.include?(header) ? header_style : auxiliary_style
      end

      sheet.add_row headers, style: header_styles

      # Procesar items y agregar datos
      item_tracker = Set.new
      row_data = []

      processed_items.each do |item|
        # Determinar flag de duplicación
        unique_flag = item_tracker.include?(item.item) ? 'AML' : 'Unique'
        item_tracker.add(item.item)

        # Lookups
        proposal_data = lookup_proposal_quote(item.item, item.mfg_partno)
        cross_ref_mpn = lookup_cross_reference(item.mfg_partno)
        total_demand = lookup_total_demand(item.item)
        min_price = lookup_min_price(item.item)

        # Si Previously Quoted = YES, forzar scope a "In scope"
        final_scope = proposal_data[:previously_quoted] == 'YES' ? 'In scope' : item.scope

        # Agregar fila de datos
        row = [
          item.sfdc_quote_number,
          item.item,
          item.mfg_partno,
          item.global_mfg_name,
          item.description,
          item.site,
          item.std_cost,
          item.last_purchase_price,
          item.last_po,
          item.eau,
          item.commodity,
          final_scope,
          unique_flag,
          cross_ref_mpn,
          item.ear_value(total_demand, min_price),
          item.ear_threshold_status(total_demand, min_price),
          proposal_data[:previously_quoted],
          proposal_data[:quote_date],
          proposal_data[:previous_sfdc_quote_number],
          proposal_data[:inx_mpn],
          total_demand,
          min_price
        ]

        sheet.add_row row
        row_data << { item: item, total_demand: total_demand, min_price: min_price }
      end

      # Aplicar formato a columnas
      sheet.col_style(6, currency_style, row_offset: 1)   # STD_COST
      sheet.col_style(7, currency_style, row_offset: 1)   # LAST_PURCHASE_PRICE
      sheet.col_style(8, currency_style, row_offset: 1)   # LAST_PO
      sheet.col_style(14, currency_style, row_offset: 1)  # EAR
      sheet.col_style(21, currency_style, row_offset: 1)  # Min Price

      sheet.col_style(9, thousands_style, row_offset: 1)  # EAU
      sheet.col_style(20, thousands_style, row_offset: 1) # Total Demand

      # Aplicar estilo especial a celdas EAR que usan fallbacks
      row_data.each_with_index do |data, index|
        row_num = index + 1  # +1 porque row 0 es header
        if data[:item].ear_uses_fallback?(data[:total_demand], data[:min_price])
          sheet.rows[row_num].cells[14].style = ear_fallback_style
          Rails.logger.debug "🟡 [STYLE] Applied yellow style to EAR for item #{data[:item].item} (uses fallback)"
        end
      end

      # Auto-filter y ajustar anchos de columna usando constante
      sheet.auto_filter = "A1:V1"
      sheet.column_widths *ExcelProcessorConfig::DEFAULT_COLUMN_WIDTHS
    end

    # Guardar el archivo
    file_path = Rails.root.join('storage', "processed_#{@processed_file.id}_#{Time.current.to_i}.xlsx")
    package.serialize(file_path)

    file_path.to_s
  end

  # ========== MÉTODOS DE CACHING MOVIDOS DESDE ExcelProcessorService ==========

  def load_proposal_quotes_cache(unique_items)
    Rails.logger.info "⚡ [CACHE] Loading proposal quotes cache..."
    start_time = Time.current

    if ENV['MOCK_SQL_SERVER'] == 'true'
      @proposal_quotes_cache = {}
      return
    end

    begin
      @proposal_quotes_cache = {}

      # Procesar en batches
      unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_items|
        quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')

        result = ItemLookup.connection.select_all(
          "SELECT ITEM, LOG_DATE, SUGAR_ID, INX_MPN
          FROM (
            SELECT ITEM, LOG_DATE, SUGAR_ID, INX_MPN,
                    ROW_NUMBER() OVER (PARTITION BY ITEM ORDER BY LOG_DATE DESC) as rn
            FROM INX_rptProposalDetailNEW
            WHERE ITEM IN (#{quoted_items})
          ) ranked
          WHERE rn = 1"
        )

        result.rows.each do |row|
          item = row[0]
          log_date = row[1]
          sugar_id = row[2]
          inx_mpn = row[3]

          @proposal_quotes_cache[item] = {
            previously_quoted: 'YES',
            quote_date: log_date,
            previous_sfdc_quote_number: sugar_id,
            inx_mpn: inx_mpn
          }
        end
      end

      load_time = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
      Rails.logger.info "⚡ [CACHE] Proposal quotes cache loaded: #{@proposal_quotes_cache.size} entries in #{load_time}ms"
    rescue => e
      Rails.logger.error "Error loading proposal quotes cache: #{e.message}"
      @proposal_quotes_cache = {}
    end
  end

  def lookup_proposal_quote(item, mfg_partno = nil)
    return nil if item.blank?

    # Si el item es igual al mfg_partno, significa que estamos usando fallback MPN
    if mfg_partno.present? && item == mfg_partno
      Rails.logger.debug "🚫 [QUOTE] Skipping MPN fallback for: #{item}"
      return {
        previously_quoted: 'NO',
        quote_date: nil,
        previous_sfdc_quote_number: nil,
        inx_mpn: nil
      }
    end

    # Si existe en cache, devolver datos
    if @proposal_quotes_cache.key?(item)
      Rails.logger.debug "✅ [QUOTE] Found #{item} in cache: YES"
      @proposal_quotes_cache[item]
    else
      Rails.logger.debug "❌ [QUOTE] #{item} NOT in cache: NO"
      {
        previously_quoted: 'NO',
        quote_date: nil,
        previous_sfdc_quote_number: nil,
        inx_mpn: nil
      }
    end
  end

  def load_aml_caches(unique_items)
    Rails.logger.info "⚡ [CACHE] Loading AML cache for #{unique_items.size} unique items..."
    start_time = Time.current

    @aml_total_demand_cache = {}
    @aml_min_price_cache = {}

    if ENV['MOCK_SQL_SERVER'] == 'true'
      mock_data = MockItemLookup.mock_aml_data
      @aml_total_demand_cache = @processed_file.enable_total_demand_lookup ? mock_data[:total_demand] : {}
      @aml_min_price_cache = mock_data[:min_price]
      return
    end

    begin
      # Procesar Total Demand en batches solo si está habilitado
      if @processed_file.enable_total_demand_lookup
        unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_items|
          quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')

          result = ItemLookup.connection.select_all(
            "SELECT ITEM, TOTAL_DEMAND
             FROM ExcelProcessorAMLfind
             WHERE ITEM IN (#{quoted_items}) AND TOTAL_DEMAND IS NOT NULL"
          )

          result.rows.each do |row|
            @aml_total_demand_cache[row[0]] = row[1]
          end
        end
      else
        Rails.logger.info "⏭️ [CACHE] Total Demand lookup disabled for this file"
      end

      # Procesar Min Price en batches
      unique_items.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_items|
        quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')

        result = ItemLookup.connection.select_all(
          "SELECT ITEM, MIN_PRICE
           FROM ExcelProcessorAMLfind
           WHERE ITEM IN (#{quoted_items}) AND MIN_PRICE IS NOT NULL"
        )

        result.rows.each do |row|
          @aml_min_price_cache[row[0]] = row[1]
        end
      end

      load_time = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
      Rails.logger.info "⚡ [CACHE] AML cache loaded: #{@aml_total_demand_cache.size} Total Demand + #{@aml_min_price_cache.size} Min Price in #{load_time}ms"
    rescue => e
      Rails.logger.error "Error loading AML cache: #{e.message}"
    end
  end

  def lookup_total_demand(item)
    return nil if item.blank?
    return nil unless @processed_file.enable_total_demand_lookup
    @aml_total_demand_cache[item.strip]
  end

  def lookup_min_price(item)
    return nil if item.blank?
    @aml_min_price_cache[item.strip]
  end

  def lookup_cross_reference(mfg_partno)
    return nil if mfg_partno.blank?
    @cross_references_cache[mfg_partno]
  end

  def load_cross_references_cache_for_mpns(unique_mpns)
    Rails.logger.info "⚡ [CACHE] Loading cross references for #{unique_mpns.size} unique MPNs..."
    start_time = Time.current

    @cross_references_cache = {}

    if ENV['MOCK_SQL_SERVER'] == 'true'
      @cross_references_cache = MockItemLookup.mock_crosses
      return
    end

    begin
      # Apply component grade filter
      include_medical_auto = @processed_file.include_medical_auto_grades || false
      grade_filter = include_medical_auto ? "AND COMPONENT_GRADE = 'AUTO'" : "AND COMPONENT_GRADE = 'COMMERCIAL'"

      # Procesar en batches
      unique_mpns.each_slice(ExcelProcessorConfig::BATCH_SIZE) do |batch_mpns|
        quoted_mpns = batch_mpns.map { |mpn| "'#{mpn.gsub("'", "''")}'" }.join(',')

        result = ItemLookup.connection.select_all(
          "SELECT CROSS_REF_MPN, INFINEX_MPN
           FROM INX_dataLabCrosses
           WHERE CROSS_REF_MPN IN (#{quoted_mpns}) AND INFINEX_MPN IS NOT NULL
           #{grade_filter}"
        )

        result.rows.each do |row|
          @cross_references_cache[row[0]] = row[1]
        end
      end

      load_time = ((Time.current - start_time) * ExcelProcessorConfig::MILLISECONDS_PER_SECOND).round(2)
      Rails.logger.info "⚡ [CACHE] Cross references loaded: #{@cross_references_cache.size} entries in #{load_time}ms"
    rescue => e
      Rails.logger.error "Error loading cross references cache: #{e.message}"
    end
  end
end