class AddMfrToCommodityReferences < ActiveRecord::Migration[7.1]
  def change
    add_column :commodity_references, :mfr, :text
  end
end
