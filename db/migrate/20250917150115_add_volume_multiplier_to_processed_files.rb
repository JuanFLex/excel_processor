class AddVolumeMultiplierToProcessedFiles < ActiveRecord::Migration[7.1]
  def change
    add_column :processed_files, :volume_multiplier, :integer
  end
end
