class CreateProcessedFiles < ActiveRecord::Migration[7.1]
  def change
    create_table :processed_files do |t|
      t.string :original_filename
      t.string :status
      t.datetime :processed_at

      t.timestamps
    end
    add_index :processed_files, :status
  end
end
