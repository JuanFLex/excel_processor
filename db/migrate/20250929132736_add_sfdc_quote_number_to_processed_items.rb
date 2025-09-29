class AddSfdcQuoteNumberToProcessedItems < ActiveRecord::Migration[7.1]
  def change
    add_column :processed_items, :sfdc_quote_number, :string

    # Copy existing sugar_id data to new sfdc_quote_number column
    reversible do |dir|
      dir.up do
        execute "UPDATE processed_items SET sfdc_quote_number = sugar_id WHERE sugar_id IS NOT NULL"
      end
    end
  end
end
