class ExcelProcessorAmlFind < ApplicationRecord
  self.abstract_class = true
  self.table_name = 'ExcelProcessorAMLfind'
  self.primary_key = 'id'

  # Reutilizar la conexión de ItemLookup en lugar de crear una nueva
  def self.connection
    ItemLookup.connection
  end

  # Método para buscar Total Demand por ITEM
  def self.lookup_total_demand_by_item(item)
    # Switch a mock si está configurado
    if ENV['MOCK_SQL_SERVER'] == 'true'
      return MockExcelProcessorAMLfind.lookup_total_demand_by_item(item)
    end
    
    return nil if item.blank?

    result = connection.select_all(
      "SELECT TOP 1 TOTAL_DEMAND
       FROM ExcelProcessorAMLfind 
       WHERE ITEM = '#{item.strip}'"
    )

    return nil if result.rows.empty?

    result.rows.first[0]
  rescue => e
    Rails.logger.error "Error en lookup Total Demand SQL Server: #{e.message}"
    nil
  end

  # Método para buscar Min Price por ITEM + MPN
  def self.lookup_min_price_by_item_mpn(item, mpn)
    # Switch a mock si está configurado
    if ENV['MOCK_SQL_SERVER'] == 'true'
      return MockExcelProcessorAMLfind.lookup_min_price_by_item_mpn(item, mpn)
    end
    
    return nil if item.blank? || mpn.blank?

    result = connection.select_all(
      "SELECT TOP 1 MIN_PRICE
       FROM ExcelProcessorAMLfind 
       WHERE ITEM = '#{item.strip}' AND MFG_PARTNO = '#{mpn.strip}'"
    )

    return nil if result.rows.empty?

    result.rows.first[0]
  rescue => e
    Rails.logger.error "Error en lookup Min Price SQL Server: #{e.message}"
    nil
  end

  # Método para buscar commodity por ITEM (para futura implementación)
  def self.lookup_commodity_by_item(item)
    # Switch a mock si está configurado
    if ENV['MOCK_SQL_SERVER'] == 'true'
      return MockExcelProcessorAMLfind.lookup_commodity_by_item(item)
    end
    
    return nil if item.blank?

    result = connection.select_all(
      "SELECT TOP 1 GLOBAL_COMM_CODE_DESC
       FROM ExcelProcessorAMLfind 
       WHERE ITEM = '#{item.strip}'"
    )

    return nil if result.rows.empty?

    result.rows.first[0]
  rescue => e
    Rails.logger.error "Error en lookup Commodity SQL Server: #{e.message}"
    nil
  end
end