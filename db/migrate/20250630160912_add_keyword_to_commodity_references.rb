class AddKeywordToCommodityReferences < ActiveRecord::Migration[7.1]
  def change
    add_column :commodity_references, :keyword, :text
  end
end
