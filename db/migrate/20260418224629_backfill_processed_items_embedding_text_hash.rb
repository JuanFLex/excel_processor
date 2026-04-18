class BackfillProcessedItemsEmbeddingTextHash < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    ProcessedItem.reset_column_information
    scope = ProcessedItem.where.not(embedding: nil).where(embedding_text_hash: nil)
    total = scope.count
    say_with_time("Backfilling #{total} processed_items embedding_text_hash") do
      scope.find_each(batch_size: 500) do |item|
        hash = ProcessedItem.hash_for_text(item.recreate_embedding_text)
        item.update_columns(embedding_text_hash: hash)
      end
    end
  end

  def down
    # no-op: la columna se elimina con el rollback de la migración anterior
  end
end
