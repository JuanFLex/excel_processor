#!/usr/bin/env ruby

# Script para analizar profundamente el problema de clasificación
puts "🔍 Análisis profundo de clasificación - Item 525355"
puts "=" * 60

begin
  require 'bundler/setup'
  require_relative 'config/environment'

  item_id = 525355
  processed_item = ProcessedItem.find_by(id: item_id)

  if processed_item.nil?
    puts "❌ Item #{item_id} no encontrado"
    exit 1
  end

  puts "✅ Item encontrado: #{processed_item.description}"
  puts "📊 Clasificación actual: #{processed_item.commodity}"
  puts "🎯 Scope actual: #{processed_item.scope}"
  puts "💰 EAU: #{processed_item.eau}"

  # 1. Comparar con el analyzer usando el método correcto
  puts "\n🧠 ANÁLISIS CON COMMODITYANALYSISSERVICE (mismo que usa el analyzer)"
  puts "-" * 60

  begin
    # Usar el mismo servicio que usa el analyzer
    result = CommodityAnalysisService.analyze_commodity_assignment(item_id)

    if result[:success]
      puts "✅ Análisis completado:"
      puts "🤖 Resultado de IA (extracto):"
      # Extraer si hay una recomendación de commodity específica
      ai_text = result[:ai_analysis]
      if ai_text.include?('CON,HIGH SPEED,INTERNAL')
        puts "   👀 ¡AI recomienda: CON,HIGH SPEED,INTERNAL I/O!"
      elsif ai_text.include?('CON,BACKPLANE')
        puts "   👀 AI confirma: CON,BACKPLANE,2MM"
      else
        puts "   📝 Análisis completo guardado en resultado"
      end

      puts "\n🎯 Top commodities similares encontrados:"
      result[:top_similares].first(3).each do |sim|
        puts "   #{sim[:posicion]}. #{sim[:nombre]} (#{sim[:similitud_porcentaje]}%)"
      end
    else
      puts "❌ Error en análisis: #{result[:error]}"
    end
  rescue => e
    puts "❌ Error ejecutando CommodityAnalysisService: #{e.message}"
  end

  # 2. Probar el método de corrección automática
  puts "\n🔄 ANÁLISIS PARA AUTO-CORRECCIÓN (mismo que usa TopEarAnalyzerJob)"
  puts "-" * 60

  begin
    correction_result = CommodityAnalysisService.analyze_for_auto_correction(item_id)

    if correction_result[:success]
      analysis = correction_result[:analysis]
      puts "✅ Análisis de corrección completado:"
      puts "   Should correct: #{analysis['should_correct']}"
      puts "   Confidence: #{analysis['confidence_level']}"
      puts "   Current correct: #{analysis['current_assignment_correct']}"
      puts "   Recommended: #{analysis['recommended_commodity']}"
      puts "   Reasoning: #{analysis['reasoning']}"
      puts "   Evidence: #{analysis['evidence']}"
    else
      puts "❌ Error en análisis de corrección: #{correction_result[:error]}"
    end
  rescue => e
    puts "❌ Error ejecutando análisis de auto-corrección: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end

  # 3. Comparar con items similares del mismo archivo
  puts "\n📋 COMPARACIÓN CON ITEMS SIMILARES DEL MISMO ARCHIVO"
  puts "-" * 60

  file = processed_item.processed_file
  similar_items = file.processed_items
                     .where("description ILIKE ?", "%CONN%")
                     .where("description ILIKE ?", "%Diff Pair%")
                     .where.not(id: item_id)
                     .limit(5)

  puts "🔍 Items similares en el mismo archivo:"
  similar_items.each do |item|
    puts "   ID: #{item.id} | EAU: #{item.eau} | #{item.commodity}"
    puts "   DESC: #{item.description[0..80]}..."
    puts
  end

  # 4. Revisar si se ejecutó TopEarAnalyzerJob
  puts "\n📈 VERIFICACIÓN DE TOP EAR ANALYZER JOB"
  puts "-" * 60

  # Buscar en logs si se procesó este archivo
  puts "📅 Archivo procesado: #{file.created_at}"
  puts "📊 Items con EAU en este archivo: #{file.processed_items.where.not(eau: [nil, 0]).count}"

  top_items = file.processed_items
                 .where.not(eau: [nil, 0])
                 .order(eau: :desc)
                 .limit(ExcelProcessorConfig::TOP_EAR_ANALYSIS_COUNT || 10)

  puts "\n🎯 TOP #{top_items.count} items por EAU (candidatos para análisis automático):"
  top_items.each_with_index do |item, index|
    marker = item.id == item_id ? "👈 NUESTRO ITEM" : ""
    puts "   #{index + 1}. ID: #{item.id}, EAU: #{item.eau}, #{item.commodity} #{marker}"
  end

  # Verificar si nuestro item está en el top que se analiza automáticamente
  is_in_top = top_items.any? { |item| item.id == item_id }
  puts "\n❓ ¿Está el item #{item_id} en el top que se analiza automáticamente? #{is_in_top ? 'SÍ ✅' : 'NO ❌'}"

  if !is_in_top
    puts "⚠️  POSIBLE CAUSA: El item no está en el top #{ExcelProcessorConfig::TOP_EAR_ANALYSIS_COUNT || 10} por EAU"
    puts "    por lo que NO se ejecutó corrección automática en él."
  end

  # 5. Recrear el texto de embedding para comparación
  puts "\n🔤 ANÁLISIS DE TEXTO DE EMBEDDING"
  puts "-" * 60

  embedding_text = processed_item.recreate_embedding_text
  puts "📝 Texto usado para embedding:"
  puts embedding_text

  # Comparar con un item bien clasificado
  well_classified = file.processed_items
                       .where(commodity: "CON,HIGH SPEED,INTERNAL I/O")
                       .first

  if well_classified
    puts "\n🎯 Comparar con item bien clasificado (#{well_classified.id}):"
    puts "   Descripción: #{well_classified.description[0..80]}..."
    puts "   Embedding text: #{well_classified.recreate_embedding_text[0..100]}..."
  end

  puts "\n✅ Análisis profundo completado."
  puts "\n🔍 RESUMEN DE HALLAZGOS:"
  puts "1. Item clasificado como CON,BACKPLANE,2MM con EAU=60000"
  puts "2. Items similares (240000 EAU) clasificados como CON,HIGH SPEED,INTERNAL I/O"
  puts "3. El analyzer debería recomendar la clasificación correcta"
  puts "4. Verificar si el problema está en el orden de procesamiento o en la lógica de embedding"

rescue => e
  puts "❌ Error general: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
