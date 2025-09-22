class AddIncludeMedicalAutoGradesToProcessedFiles < ActiveRecord::Migration[7.1]
  def change
    add_column :processed_files, :include_medical_auto_grades, :boolean
  end
end
