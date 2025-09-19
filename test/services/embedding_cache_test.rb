require 'test_helper'

class EmbeddingCacheTest < ActiveSupport::TestCase
  def setup
    @processed_file = ProcessedFile.create!(
      original_filename: 'test_cache.xlsx',
      status: 'completed'
    )
  end

  test "embedding text consistency after save" do
    item = ProcessedItem.create!(
      processed_file: @processed_file,
      item: 'TEST-RESISTOR',
      mfg_partno: 'R1K',
      global_mfg_name: 'Test Mfg',
      description: 'Test resistor 1k ohm'
    )

    # Capture original embedding text
    original_text = item.recreate_embedding_text

    # Save embedding (simulating normal flow)
    item.update!(embedding: [0.1, 0.2, 0.3] * 128)  # Mock embedding

    # Verify text remains identical
    current_text = item.recreate_embedding_text
    assert_equal original_text, current_text,
                 "Embedding text changed after saving embedding - cache will not work"
  end

  test "cache finds existing embeddings with correct text matching" do
    # Create item with embedding
    item = ProcessedItem.create!(
      processed_file: @processed_file,
      item: 'TEST-CAPACITOR',
      mfg_partno: 'C100',
      global_mfg_name: 'Test Mfg',
      description: 'Test capacitor 100nF',
      embedding: [0.4, 0.5, 0.6] * 128
    )

    embedding_text = item.recreate_embedding_text

    # Test cache lookup
    cache_result = OpenaiService.send(:preload_embeddings_from_db_batched, [embedding_text])

    # Should find the embedding
    assert cache_result[embedding_text].present?,
           "Cache should find existing embedding for same text"
    assert_equal item.embedding, cache_result[embedding_text],
                 "Cache should return correct embedding data"
  end

  test "cache misses when embedding text is different" do
    # Create item with embedding
    item = ProcessedItem.create!(
      processed_file: @processed_file,
      item: 'TEST-INDUCTOR',
      mfg_partno: 'L100',
      global_mfg_name: 'Test Mfg',
      description: 'Test inductor 100uH',
      embedding: [0.7, 0.8, 0.9] * 128
    )

    # Search for different text
    different_text = "Product: DIFFERENT-ITEM\nDescription: Different description"

    cache_result = OpenaiService.send(:preload_embeddings_from_db_batched, [different_text])

    # Should not find anything
    assert cache_result[different_text].blank?,
           "Cache should not find embedding for different text"
  end

  test "recreate_embedding_text generates consistent format" do
    item = ProcessedItem.create!(
      processed_file: @processed_file,
      item: 'TEST-ITEM',
      mfg_partno: 'MPN123',
      global_mfg_name: 'Test Manufacturer',
      description: 'Test description with special chars: & < >'
    )

    text = item.recreate_embedding_text

    # Should contain expected components
    assert_includes text, "Product: TEST-ITEM"
    assert_includes text, "MPN: MPN123"
    assert_includes text, "Manufacturer: Test Manufacturer"
    assert_includes text, "Description:"

    # Should be consistent across multiple calls
    assert_equal text, item.recreate_embedding_text
    assert_equal text, item.recreate_embedding_text
  end

  test "cache performance with multiple items" do
    # Create multiple items with embeddings
    items = []
    embedding_texts = []

    5.times do |i|
      item = ProcessedItem.create!(
        processed_file: @processed_file,
        item: "TEST-ITEM-#{i}",
        mfg_partno: "MPN#{i}",
        global_mfg_name: 'Test Mfg',
        description: "Test description #{i}",
        embedding: [i * 0.1, i * 0.2, i * 0.3] * 128
      )
      items << item
      embedding_texts << item.recreate_embedding_text
    end

    # Test batch cache lookup
    start_time = Time.current
    cache_result = OpenaiService.send(:preload_embeddings_from_db_batched, embedding_texts)
    elapsed_ms = ((Time.current - start_time) * 1000).round(2)

    # Should find all embeddings
    assert_equal 5, cache_result.size, "Should find all 5 embeddings in cache"

    embedding_texts.each do |text|
      assert cache_result[text].present?, "Should find embedding for text: #{text[0..30]}..."
    end

    # Log performance for monitoring
    puts "✅ Cache lookup for 5 items: #{elapsed_ms}ms"
  end
end