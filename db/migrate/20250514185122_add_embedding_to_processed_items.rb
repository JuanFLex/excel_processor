class AddEmbeddingToProcessedItems < ActiveRecord::Migration[7.1]
  def change
    add_column :processed_items, :embedding, :jsonb
  end
end
