class ItemLookup < ApplicationRecord
    self.abstract_class = true
    self.table_name = 'INX_dataLabCrosses'
    self.primary_key = 'INX_dataLabCrossesID'

    # Configuración para SQL Server
    SQL_SERVER_CONFIG = {
      adapter: 'sqlserver',
      host: '10.5.3.241',  # TEMPORAL: usando IP mientras IT arregla DNS de K-LNT5256
      port: 15001,
      database: 'p_infinex',
      username: Rails.application.credentials.dig(:sqlserver, :username),
      password: Rails.application.credentials.dig(:sqlserver, :password),
      timeout: 5000
    }.freeze

    establish_connection(SQL_SERVER_CONFIG)

    # Método simple para lookup por SUPPLIER_PN 
    def self.lookup_by_supplier_pn(mfg_partno)
      # Switch a mock si está configurado
      if ENV['MOCK_SQL_SERVER'] == 'true'
        return MockItemLookup.lookup_by_supplier_pn(mfg_partno)
      end
      
      return nil if mfg_partno.blank?

      result = connection.select_all(
        "SELECT SUPPLIER_PN, INFINEX_MPN, INFINEX_COST, CROSS_REF_MFG
        FROM (
            select  
                ROW_NUMBER() OVER(PARTITION BY SUPPLIER_PN, CROSS_REF_MFG ORDER BY INFINEX_COST ASC) AS RN,
                *
            from INX_dataLabCrosses 
            WHERE CROSS_REF_MPN = '#{mfg_partno}'
            ) QUERY
            WHERE RN = 1"
      )

      return nil if result.rows.empty?

      row = result.rows.first
      {
        supplier_pn: row[0],
        mpn: row[1],
        cw_cost: row[2],
        manufacturer: row[3]
      }
    rescue => e
      Rails.logger.error "Error en lookup SQL Server: #{e.message}"
      nil
    end
  end
