class CreateCommodityReferences < ActiveRecord::Migration[7.1]
  def change
    create_table :commodity_references do |t|
      t.string :global_comm_code_desc
      t.string :level1_desc
      t.string :level2_desc
      t.string :level3_desc
      t.string :infinex_scope_status
      t.jsonb :embedding

      t.timestamps
    end

    add_index :commodity_references, :level2_desc
    add_index :commodity_references, :infinex_scope_status
  end
end
