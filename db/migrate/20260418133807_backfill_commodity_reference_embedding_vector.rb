class BackfillCommodityReferenceEmbeddingVector < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL
      UPDATE commodity_references
      SET embedding_vector = (embedding::text)::vector
      WHERE embedding IS NOT NULL
        AND embedding_vector IS NULL
    SQL
  end

  def down
    execute "UPDATE commodity_references SET embedding_vector = NULL"
  end
end
