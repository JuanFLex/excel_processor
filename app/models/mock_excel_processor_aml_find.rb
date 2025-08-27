class MockExcelProcessorAMLfind
  # Mock data para testing
  MOCK_DATA = [
    { item: 'ITEM001', mpn: 'MPN001', total_demand: 150, min_price: 25.50, global_comm_code_desc: 'Electronic Components' },
    { item: 'ITEM002', mpn: 'MPN002', total_demand: 300, min_price: 12.75, global_comm_code_desc: 'Mechanical Parts' },
    { item: 'ITEM003', mpn: 'MPN003', total_demand: 75, min_price: 45.20, global_comm_code_desc: 'Electrical Components' },
    { item: 'TEST_ITEM', mpn: 'TEST_MPN', total_demand: 100, min_price: 15.00, global_comm_code_desc: 'Test Category' }
  ].freeze

  def self.lookup_total_demand_by_item(item)
    return nil if item.blank?
    
    mock_item = MOCK_DATA.find { |data| data[:item] == item.strip }
    mock_item&.dig(:total_demand)
  end

  def self.lookup_min_price_by_item_mpn(item, mpn)
    return nil if item.blank? || mpn.blank?
    
    mock_item = MOCK_DATA.find do |data| 
      data[:item] == item.strip && data[:mpn] == mpn.strip
    end
    
    mock_item&.dig(:min_price)
  end

  def self.lookup_commodity_by_item(item)
    return nil if item.blank?
    
    mock_item = MOCK_DATA.find { |data| data[:item] == item.strip }
    mock_item&.dig(:global_comm_code_desc)
  end
end