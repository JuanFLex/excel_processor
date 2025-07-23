require 'test_helper'

class OpenaiServiceTest < ActiveSupport::TestCase
  def setup
    # Limpiar cache para tests limpios
    OpenaiService.embeddings_cache.clear if OpenaiService.embeddings_cache
    
    # Reset rate limiter
    OpenaiService.tokens_per_minute = 0
    OpenaiService.minute_start = Time.current.beginning_of_minute
  end

  test "basic embedding functionality with real OpenAI API" do
    skip "Skipping OpenAI API test - set OPENAI_API_KEY to run" unless ENV['OPENAI_API_KEY']
    
    text = "hola mundo"
    
    # Test single embedding
    embedding = OpenaiService.get_embedding_for_text(text)
    
    assert embedding.present?, "Embedding should not be nil"
    assert embedding.is_a?(Array), "Embedding should be an array"
    assert_equal 1536, embedding.size, "text-embedding-3-small should return 1536 dimensions"
    assert embedding.all? { |val| val.is_a?(Float) }, "All embedding values should be floats"
    
    puts "✅ Basic embedding test passed - OpenAI API is working"
    puts "📊 Embedding size: #{embedding.size}"
    puts "📏 First 5 values: #{embedding.first(5)}"
  end

  test "batch embeddings functionality" do
    skip "Skipping OpenAI API test - set OPENAI_API_KEY to run" unless ENV['OPENAI_API_KEY']
    
    texts = ["hola mundo", "hello world", "motor electrico", "bomba hidraulica"]
    
    embeddings = OpenaiService.get_embeddings(texts)
    
    assert_equal texts.size, embeddings.size, "Should return same number of embeddings as texts"
    
    embeddings.each_with_index do |embedding, index|
      assert embedding.present?, "Embedding #{index} should not be nil"
      assert embedding.is_a?(Array), "Embedding #{index} should be an array"
      assert_equal 1536, embedding.size, "Embedding #{index} should have 1536 dimensions"
    end
    
    puts "✅ Batch embeddings test passed"
    puts "📊 Processed #{texts.size} texts successfully"
  end

  test "embedding cache functionality" do
    skip "Skipping OpenAI API test - set OPENAI_API_KEY to run" unless ENV['OPENAI_API_KEY']
    
    text = "test cache functionality"
    
    # First call - should hit OpenAI
    start_time = Time.current
    embedding1 = OpenaiService.get_embedding_for_text(text)
    first_call_time = Time.current - start_time
    
    # Second call - should use cache
    start_time = Time.current
    embedding2 = OpenaiService.get_embedding_for_text(text)
    second_call_time = Time.current - start_time
    
    assert_equal embedding1, embedding2, "Cached embedding should be identical"
    assert second_call_time < first_call_time, "Second call should be faster (cached)"
    
    puts "✅ Cache test passed"
    puts "⚡ First call: #{(first_call_time * 1000).round(2)}ms"
    puts "⚡ Second call (cached): #{(second_call_time * 1000).round(2)}ms"
  end

  test "rate limiter functionality" do
    # Test token estimation
    text = "this is a test text for token estimation"
    estimated_tokens = OpenaiService.send(:estimate_tokens, text)
    
    expected_tokens = (text.length / 4.0).ceil
    assert_equal expected_tokens, estimated_tokens, "Token estimation should be text.length / 4"
    
    puts "✅ Token estimation test passed"
    puts "📏 Text: '#{text}'"
    puts "📊 Length: #{text.length} chars"
    puts "🎯 Estimated tokens: #{estimated_tokens}"
  end

  test "database embedding cache functionality" do
    skip "Skipping DB test - requires database connection" unless ActiveRecord::Base.connected?
    
    # Limpiar datos de prueba
    ProcessedItem.destroy_all
    
    # Crear un item con embedding para simular cache en BD
    test_description = "motor electrico test"
    test_embedding = Array.new(1536) { rand(-1.0..1.0) }  # Embedding simulado
    
    ProcessedItem.create!(
      processed_file_id: 1,  # ID falso para test
      description: test_description,
      embedding: test_embedding,
      commodity: "TEST",
      scope: "Test"
    )
    
    # Test que encuentra el embedding en BD
    found_embedding = OpenaiService.send(:find_embedding_in_db, test_description)
    
    assert_equal test_embedding, found_embedding, "Should find embedding in database"
    
    puts "✅ Database cache test passed"
    puts "💾 Found cached embedding for: '#{test_description}'"
  end

  test "manufacturer standardization functionality" do
    skip "Skipping manufacturer test - requires database connection" unless ActiveRecord::Base.connected?
    
    # Limpiar y crear datos de prueba
    ManufacturerMapping.destroy_all
    
    ManufacturerMapping.create!([
      { original_name: "SAMSUNG CO", standardized_name: "SAMSUNG INC" },
      { original_name: "SAMSUNG ELECTRONICS", standardized_name: "SAMSUNG INC" },
      { original_name: "SAMSUMG ELECTRIC", standardized_name: "SAMSUNG INC" }
    ])
    
    # Test standardization
    assert_equal "SAMSUNG INC", ManufacturerMapping.standardize("SAMSUNG CO")
    assert_equal "SAMSUNG INC", ManufacturerMapping.standardize("SAMSUNG ELECTRONICS")
    assert_equal "SAMSUNG INC", ManufacturerMapping.standardize("SAMSUMG ELECTRIC")
    assert_equal "UNKNOWN MFG", ManufacturerMapping.standardize("UNKNOWN MFG")  # No mapping
    
    puts "✅ Manufacturer standardization test passed"
    puts "🏭 SAMSUNG variants → SAMSUNG INC"
  end
end