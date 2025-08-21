class AddTypicalMpnByManufacturerToCommodityReferences < ActiveRecord::Migration[7.1]
  def change
    add_column :commodity_references, :typical_mpn_by_manufacturer, :text
  end
end
