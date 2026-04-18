class AddEmbeddingTextHashToProcessedItems < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :processed_items, :embedding_text_hash, :string, limit: 64
    add_index  :processed_items, :embedding_text_hash,
               name: "index_processed_items_on_embedding_text_hash",
               algorithm: :concurrently
  end
end
