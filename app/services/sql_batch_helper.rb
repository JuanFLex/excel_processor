class SqlBatchHelper
  def self.process_in_batches(items, batch_size: ExcelProcessorConfig::BATCH_SIZE)
    items.each_slice(batch_size) do |batch_items|
      quoted_items = batch_items.map { |item| "'#{item.gsub("'", "''")}'" }.join(',')
      yield(quoted_items, batch_items)
    end
  end
end