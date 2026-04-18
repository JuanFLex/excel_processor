class EnablePgvectorAndAddVectorColumns < ActiveRecord::Migration[7.1]
  def change
    enable_extension "vector"
    add_column :commodity_references, :embedding_vector, :vector, limit: 1536
  end
end
