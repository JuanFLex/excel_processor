class AddEnableTotalDemandLookupToProcessedFiles < ActiveRecord::Migration[7.1]
  def change
    add_column :processed_files, :enable_total_demand_lookup, :boolean
  end
end
