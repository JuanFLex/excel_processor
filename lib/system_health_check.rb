# frozen_string_literal: true

# Sistema de diagnóstico completo para Excel Processor
# Valida todas las funciones críticas del sistema

class SystemHealthCheck
  def self.run_full_diagnosis
    checker = new
    puts "🏥 DIAGNÓSTICO COMPLETO DEL SISTEMA"
    puts "=" * 60
    puts "#{Time.current.strftime('%Y-%m-%d %H:%M:%S')} - Iniciando diagnóstico..."
    puts
    
    # Ejecutar todas las pruebas
    results = {
      database: checker.test_database_connections,
      sql_server: checker.test_sql_server_integration,
      openai: checker.test_openai_integration,
      embeddings: checker.test_embeddings_system,
      commodity_analysis: checker.test_commodity_analysis,
      file_processing: checker.test_file_processing_pipeline,
      cache_systems: checker.test_cache_systems
    }
    
    # Resumen final
    checker.print_final_summary(results)
    
    results
  end
  
  def test_database_connections
    puts "🗄️  PRUEBA 1: CONEXIONES DE BASE DE DATOS"
    puts "-" * 40
    
    results = { status: :ok, details: [], errors: [] }
    
    begin
      # PostgreSQL (principal)
      pg_result = ActiveRecord::Base.connection.execute("SELECT version()")
      pg_version = pg_result.first['version'].split(' ')[1]
      results[:details] << "✅ PostgreSQL conectado (v#{pg_version})"
      
      # Verificar tablas críticas
      critical_tables = %w[processed_files processed_items commodity_references users]
      critical_tables.each do |table|
        count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table}").first['count']
        results[:details] << "✅ Tabla #{table}: #{count} registros"
      end
      
    rescue => e
      results[:status] = :error
      results[:errors] << "❌ PostgreSQL: #{e.message}"
    end
    
    print_section_results(results)
    results
  end
  
  def test_sql_server_integration
    puts "🔗 PRUEBA 2: INTEGRACIÓN CON SQL SERVER"
    puts "-" * 40
    
    results = { status: :ok, details: [], errors: [] }
    
    if ENV['MOCK_SQL_SERVER'] == 'true'
      results[:details] << "🎭 MODO MOCK activo - usando datos simulados"
      return results
    end
    
    begin
      # Test conexión básica
      test_query = "SELECT TOP 1 ITEM FROM ExcelProcessorAMLfind"
      result = ItemLookup.connection.execute(test_query)
      results[:details] << "✅ SQL Server conectado"
      
      # Test Total Demand
      demand_query = "SELECT TOP 3 ITEM, TOTAL_DEMAND FROM ExcelProcessorAMLfind WHERE TOTAL_DEMAND IS NOT NULL"
      demand_result = ItemLookup.connection.select_all(demand_query)
      results[:details] << "✅ Total Demand: #{demand_result.rows.size} registros de prueba"
      
      # Test Min Price  
      price_query = "SELECT TOP 3 ITEM, MIN_PRICE FROM ExcelProcessorAMLfind WHERE MIN_PRICE IS NOT NULL"
      price_result = ItemLookup.connection.select_all(price_query)
      results[:details] << "✅ Min Price: #{price_result.rows.size} registros de prueba"
      
      # Test Cross References
      cross_query = "SELECT TOP 3 CROSS_REF_MPN FROM INX_dataLabCrosses WHERE INFINEX_MPN IS NOT NULL"
      cross_result = ItemLookup.connection.select_all(cross_query)
      results[:details] << "✅ Cross References: #{cross_result.rows.size} registros de prueba"
      
    rescue => e
      results[:status] = :error
      results[:errors] << "❌ SQL Server: #{e.message}"
    end
    
    print_section_results(results)
    results
  end
  
  def test_openai_integration
    puts "🤖 PRUEBA 3: INTEGRACIÓN CON OPENAI"
    puts "-" * 40
    
    results = { status: :ok, details: [], errors: [] }
    
    if ENV['MOCK_OPENAI'] == 'true'
      results[:details] << "🎭 MODO MOCK activo - usando respuestas simuladas"
      
      # Test mock embeddings
      mock_embeddings = MockOpenaiService.get_embeddings(['test component description'])
      if mock_embeddings&.first&.is_a?(Array) && mock_embeddings.first.size == 1536
        results[:details] << "✅ Mock Embeddings: Generando vectores de 1536 dimensiones"
      else
        results[:status] = :error
        results[:errors] << "❌ Mock Embeddings falló"
      end
      
      return print_section_results(results) && results
    end
    
    begin
      # Test embeddings reales
      test_text = "Electronic component resistor 1k ohm"
      embedding = OpenaiService.get_embedding_for_text(test_text)
      
      if embedding&.is_a?(Array) && embedding.size == 1536
        results[:details] << "✅ Embeddings: Vector de #{embedding.size} dimensiones generado"
      else
        results[:status] = :error
        results[:errors] << "❌ Embeddings: Respuesta inválida"
      end
      
      # Test completion
      test_prompt = "Analyze this component: resistor 1k ohm. Provide classification."
      completion = OpenaiService.get_completion(test_prompt, 100)
      
      if completion&.is_a?(String) && completion.length > 10
        results[:details] << "✅ Completions: Respuesta de #{completion.length} caracteres"
      else
        results[:status] = :error  
        results[:errors] << "❌ Completions: Sin respuesta válida"
      end
      
    rescue => e
      results[:status] = :error
      results[:errors] << "❌ OpenAI: #{e.message}"
    end
    
    print_section_results(results)
    results
  end
  
  def test_embeddings_system
    puts "🧠 PRUEBA 4: SISTEMA DE EMBEDDINGS Y SIMILITUD"
    puts "-" * 40
    
    results = { status: :ok, details: [], errors: [] }
    
    begin
      # Verificar commodity references con embeddings
      commodities_with_embeddings = CommodityReference.where.not(embedding: nil).count
      total_commodities = CommodityReference.count
      
      if commodities_with_embeddings > 0
        percentage = (commodities_with_embeddings * 100.0 / total_commodities).round(1)
        results[:details] << "✅ Commodity References: #{commodities_with_embeddings}/#{total_commodities} tienen embeddings (#{percentage}%)"
      else
        results[:status] = :warning
        results[:errors] << "⚠️  No hay commodity references con embeddings"
      end
      
      # Test processed items con embeddings
      items_with_embeddings = ProcessedItem.where.not(embedding: nil).count
      if items_with_embeddings > 0
        results[:details] << "✅ Processed Items: #{items_with_embeddings} con embeddings"
        
        # Test similitud
        test_item = ProcessedItem.where.not(embedding: nil).first
        if test_item && commodities_with_embeddings > 0
          similar = CommodityReference.find_most_similar(test_item.embedding, 3)
          if similar.any?
            top_similarity = test_item.embedding.zip(similar.first.embedding).sum { |a, b| a * b }
            results[:details] << "✅ Búsqueda de similitud: Top match #{(top_similarity * 100).round(1)}%"
          end
        end
      else
        results[:status] = :warning
        results[:errors] << "⚠️  No hay processed items con embeddings para probar"
      end
      
    rescue => e
      results[:status] = :error
      results[:errors] << "❌ Sistema de embeddings: #{e.message}"
    end
    
    print_section_results(results)
    results
  end
  
  def test_commodity_analysis
    puts "🔍 PRUEBA 5: ANÁLISIS DE COMMODITIES CON IA"
    puts "-" * 40
    
    results = { status: :ok, details: [], errors: [] }
    
    begin
      # Buscar un item con embedding para analizar
      test_item = ProcessedItem.where.not(embedding: nil).first
      
      if test_item.nil?
        results[:status] = :warning
        results[:errors] << "⚠️  No hay items con embeddings para probar análisis"
        return print_section_results(results) && results
      end
      
      # Test recreate_embedding_text
      embedding_text = test_item.recreate_embedding_text
      if embedding_text.present?
        results[:details] << "✅ Recreación de texto de embedding: #{embedding_text.length} caracteres"
      else
        results[:errors] << "❌ No se pudo recrear texto de embedding"
      end
      
      # Test análisis completo (solo si no es mock para no gastar tokens)
      if ENV['MOCK_OPENAI'] != 'true' && CommodityReference.where.not(embedding: nil).count > 0
        analysis = CommodityAnalysisService.analyze_commodity_assignment(test_item.id)
        
        if analysis[:success] && analysis[:ai_analysis].present?
          results[:details] << "✅ Análisis con IA: #{analysis[:ai_analysis].length} caracteres de respuesta"
          results[:details] << "✅ Top 5 similares: #{analysis[:top_5_similares].size} commodities"
        else
          results[:errors] << "❌ Análisis con IA falló"
        end
      else
        results[:details] << "🎭 Análisis IA: Saltado (modo mock o sin referencias)"
      end
      
    rescue => e
      results[:status] = :error
      results[:errors] << "❌ Análisis de commodities: #{e.message}"
    end
    
    print_section_results(results)
    results
  end
  
  def test_file_processing_pipeline
    puts "⚙️  PRUEBA 6: PIPELINE DE PROCESAMIENTO"
    puts "-" * 40
    
    results = { status: :ok, details: [], errors: [] }
    
    begin
      # Verificar archivos procesados recientes
      recent_files = ProcessedFile.where(status: 'completed').limit(5)
      if recent_files.any?
        results[:details] << "✅ Archivos completados: #{recent_files.count} archivos recientes"
        
        # Verificar archivo más reciente
        latest_file = recent_files.first
        items_count = latest_file.processed_items.count
        results[:details] << "✅ Último archivo: #{items_count} items procesados"
        
        # Verificar commodities asignados
        commodities_assigned = latest_file.processed_items.where.not(commodity: ['Unknown', nil, '']).count
        assignment_rate = (commodities_assigned * 100.0 / items_count).round(1)
        results[:details] << "✅ Asignación de commodities: #{assignment_rate}% exitosa"
        
        # Verificar scopes
        in_scope_count = latest_file.processed_items.where(scope: 'In scope').count
        scope_rate = (in_scope_count * 100.0 / items_count).round(1)
        results[:details] << "✅ Items in scope: #{scope_rate}%"
        
      else
        results[:status] = :warning
        results[:errors] << "⚠️  No hay archivos completados para verificar"
      end
      
      # Test servicios críticos
      if ProcessedFile.any?
        latest_file = ProcessedFile.last
        service = ExcelProcessorService.new(latest_file)
        results[:details] << "✅ ExcelProcessorService: Inicializado correctamente"
      end
      
    rescue => e
      results[:status] = :error
      results[:errors] << "❌ Pipeline de procesamiento: #{e.message}"
    end
    
    print_section_results(results)
    results
  end
  
  def test_cache_systems
    puts "💾 PRUEBA 7: SISTEMAS DE CACHÉ"
    puts "-" * 40
    
    results = { status: :ok, details: [], errors: [] }
    
    begin
      if ProcessedFile.any?
        test_file = ProcessedFile.last
        service = ExcelProcessorService.new(test_file)
        
        # Test AML cache
        test_items = test_file.processed_items.limit(3).pluck(:item)
        if test_items.any?
          service.send(:load_aml_cache_for_items, test_items)
          
          total_demand_cache = service.instance_variable_get(:@aml_total_demand_cache)
          min_price_cache = service.instance_variable_get(:@aml_min_price_cache)
          
          results[:details] << "✅ AML Cache: #{total_demand_cache.size} Total Demand + #{min_price_cache.size} Min Price"
        end
        
        # Test OpenAI embeddings cache
        OpenaiService.embeddings_cache.clear if OpenaiService.embeddings_cache
        test_embeddings = OpenaiService.get_embeddings(['test cache'])
        cache_size = OpenaiService.embeddings_cache&.size || 0
        results[:details] << "✅ Embeddings Cache: #{cache_size} entradas"
        
      else
        results[:details] << "⚠️  No hay archivos para probar cache"
      end
      
    rescue => e
      results[:status] = :error
      results[:errors] << "❌ Sistemas de caché: #{e.message}"
    end
    
    print_section_results(results)
    results
  end
  
  def print_final_summary(results)
    puts "📊 RESUMEN FINAL DEL DIAGNÓSTICO"
    puts "=" * 60
    
    ok_count = results.values.count { |r| r[:status] == :ok }
    warning_count = results.values.count { |r| r[:status] == :warning }
    error_count = results.values.count { |r| r[:status] == :error }
    total_tests = results.size
    
    puts "Total de pruebas: #{total_tests}"
    puts "✅ Exitosas: #{ok_count}"
    puts "⚠️  Advertencias: #{warning_count}"
    puts "❌ Errores: #{error_count}"
    puts
    
    overall_health = if error_count == 0 && warning_count <= 1
                       "🟢 SISTEMA SALUDABLE"
                     elsif error_count <= 1 && warning_count <= 2
                       "🟡 SISTEMA FUNCIONAL CON OBSERVACIONES"
                     else
                       "🔴 SISTEMA REQUIERE ATENCIÓN"
                     end
    
    puts "Estado general: #{overall_health}"
    puts
    puts "Diagnóstico completado: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
  end

  private
  
  def print_section_results(results)
    results[:details].each { |detail| puts detail }
    results[:errors].each { |error| puts error }
    
    status_icon = case results[:status]
                  when :ok then "✅"
                  when :warning then "⚠️ "
                  when :error then "❌"
                  end
    
    puts "#{status_icon} Estado: #{results[:status].upcase}"
    puts
  end
end

# Para usar en Rails console:
if defined?(Rails::Console)
  puts "🏥 Sistema de diagnóstico cargado!"
  puts "Ejecuta: SystemHealthCheck.run_full_diagnosis"
end