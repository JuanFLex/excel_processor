class AddMissingColumnsToProcessedFiles < ActiveRecord::Migration[7.1]
  def change
    add_column :processed_files, :column_mapping, :jsonb
    add_column :processed_files, :result_file_path, :string
    add_column :processed_files, :error_message, :text
  end
end
