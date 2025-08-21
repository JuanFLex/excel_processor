namespace :commodities do
  desc "Actualizar embeddings para referencias de commodities"
  task update_embeddings: :environment do
    CommodityEmbeddingsUpdaterJob.perform_now
  end
  
  desc "Regenerar embedding para un commodity específico por ID"
  task :regenerate_embedding, [:id] => :environment do |t, args|
    id = args[:id]
    
    if id.blank?
      puts "❌ Error: Debes proporcionar un ID"
      puts "Uso: rails commodities:regenerate_embedding[123]"
      exit 1
    end
    
    commodity = CommodityReference.find_by(id: id)
    
    if commodity.nil?
      puts "❌ Error: No se encontró commodity con ID #{id}"
      exit 1
    end
    
    puts "🔄 Regenerando embedding para: #{commodity.level3_desc}"
    
    if commodity.regenerate_embedding!
      puts "✅ Embedding regenerado exitosamente"
    else
      puts "❌ Error al regenerar embedding"
      exit 1
    end
  end
  
  desc "Regenerar embeddings para commodities sin embedding"
  task regenerate_missing_embeddings: :environment do
    commodities = CommodityReference.where(embedding: nil)
    total = commodities.count
    
    if total == 0
      puts "✅ Todos los commodities ya tienen embeddings"
      exit
    end
    
    puts "🔄 Regenerando embeddings para #{total} commodities sin embedding..."
    
    success_count = 0
    commodities.find_each.with_index do |commodity, index|
      print "Procesando #{index + 1}/#{total}: #{commodity.level3_desc}... "
      
      if commodity.regenerate_embedding!
        success_count += 1
        puts "✅"
      else
        puts "❌"
      end
      
      # Pequeña pausa para no saturar OpenAI API
      sleep(0.5) if (index + 1) % 10 == 0
    end
    
    puts "\n📊 Resumen:"
    puts "✅ Exitosos: #{success_count}"
    puts "❌ Fallidos: #{total - success_count}"
  end
end