class AddLevel3DescExpandedToCommodityReferences < ActiveRecord::Migration[7.1]
  def change
    add_column :commodity_references, :level3_desc_expanded, :text
  end
end
