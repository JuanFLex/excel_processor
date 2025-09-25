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
    def self.lookup_by_supplier_pn(mfg_partno, include_medical_auto_grades: false)
      # Switch a mock si está configurado
      if ENV['MOCK_SQL_SERVER'] == 'true'
        return MockItemLookup.lookup_by_supplier_pn(mfg_partno, include_medical_auto_grades: include_medical_auto_grades)
      end

      return nil if mfg_partno.blank?

      # Construir la condición adicional para excluir MEDICAL y AUTO grades
      grade_filter = include_medical_auto_grades ? "AND COMPONENT_GRADE = 'AUTO'" : "AND COMPONENT_GRADE = 'COMMERCIAL'"


      result = connection.select_all(
        "SELECT SUPPLIER_PN, INFINEX_MPN, INFINEX_COST, CROSS_REF_MFG
        FROM (
            select
                ROW_NUMBER() OVER(PARTITION BY SUPPLIER_PN, CROSS_REF_MFG ORDER BY INFINEX_COST ASC) AS RN,
                *
            from INX_dataLabCrosses
            WHERE CROSS_REF_MPN = '#{mfg_partno}'
                AND INFINEX_MPN IS NOT NULL
                AND LTRIM(RTRIM(INFINEX_MPN)) <> ''
                #{grade_filter}
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

    # Método para lookup de oportunidades
    def self.lookup_opportunity(opportunity_number)
      return nil if opportunity_number.blank?

      # Switch a mock si está configurado
      if ENV['MOCK_SQL_SERVER'] == 'true'
        return MockItemLookup.lookup_opportunity(opportunity_number)
      end

      begin
        result = connection.select_all(
          "SELECT
            OPPORTUNITY_NUMBER,
            [opp.Name (Name)] AS OPPORTUNITY_NAME,
            [opp.Account_Name__c (Account Name)] AS CUSTOMER,
            [opp.Probability (Probability (%))] AS PROBABILITY,
            [opp.CloseDate (Close Date)] AS TARGETED_QUOTE_DEADLINE,
            [opp.Product_Type_Segment__c (Product Type (Segment))] AS PRODUCT_APPLICATION,
            [opp.Sales_BU__c (Sales Segment)] AS BU,
            [opp.StageName (Stage)] AS STAGE,
            [opp.Expected_Annualized_Revenue__c (EAR-Estimated Annualized Revenue ($M))] AS EAR,
            [target_site_1_name_c] AS SITE_1,
            [user.Name (Opp Owner Full Name)] AS BD_OWNER,
            [Production Ramp Start Date] as SOP_DATE
          FROM CSG_rptSFDC
          WHERE [Primary Service Group] = 'Coreworks'
            AND OPPORTUNITY_NUMBER = '#{opportunity_number}'"
        )

        return nil if result.rows.empty?

        row = result.rows.first
        {
          opportunity_number: row[0],
          opportunity_name: row[1],
          customer: row[2],
          probability: row[3],
          targeted_quote_deadline: row[4],
          product_application: row[5],
          bu: row[6],
          stage: row[7],
          ear: row[8],
          site_1: row[9],
          bd_owner: row[10],
          sop_date: row[11]
        }
      rescue => e
        Rails.logger.error "Error en opportunity lookup SQL Server: #{e.message}"
        nil
      end
    end
  end
