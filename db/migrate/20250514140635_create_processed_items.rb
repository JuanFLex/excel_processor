class CreateProcessedItems < ActiveRecord::Migration[7.1]
  def change
    create_table :processed_items do |t|
      t.references :processed_file, null: false, foreign_key: true
      t.string :sugar_id
      t.string :item
      t.string :mfg_partno
      t.string :global_mfg_name
      t.text :description
      t.string :site
      t.decimal :std_cost
      t.decimal :last_purchase_price
      t.decimal :last_po
      t.integer :eau
      t.string :commodity
      t.string :scope

      t.timestamps
    end
    add_index :processed_items, :item
    add_index :processed_items, :mfg_partno
    add_index :processed_items, :commodity
  end
end
