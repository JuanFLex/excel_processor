class AddHnswIndexToCommodityReferenceEmbeddingVector < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :commodity_references, :embedding_vector,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "idx_commodity_references_embedding_vector_hnsw",
              algorithm: :concurrently
  end
end
