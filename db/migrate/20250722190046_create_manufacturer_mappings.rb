class CreateManufacturerMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :manufacturer_mappings do |t|
      t.string :original_name, null: false
      t.string :standardized_name, null: false

      t.timestamps
    end
    
    add_index :manufacturer_mappings, :original_name
  end
end
