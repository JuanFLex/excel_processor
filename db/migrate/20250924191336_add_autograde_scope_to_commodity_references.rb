class AddAutogradeScopeToCommodityReferences < ActiveRecord::Migration[7.1]
  def change
    add_column :commodity_references, :autograde_scope, :string
    add_index :commodity_references, :autograde_scope
  end
end
