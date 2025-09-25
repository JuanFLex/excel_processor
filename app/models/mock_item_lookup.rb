class MockItemLookup
  # Mock para ItemLookup cuando no hay acceso a SQL Server
  
  # Método para acceder a los datos mock desde ExcelProcessorService
  def self.mock_crosses
    {
      # Packaging items
      'PKG-001' => { 
        supplier_pn: 'SUP-PKG-001', 
        mpn: 'CW-PKG-001', 
        cw_cost: 15.50, 
        manufacturer: 'PACKAGING CORP' 
      },
      'PKG-002' => { 
        supplier_pn: 'SUP-PKG-002', 
        mpn: 'CW-PKG-002', 
        cw_cost: 22.75, 
        manufacturer: 'PACK SOLUTIONS' 
      },
      
      # Hardware items  
      'HW-001' => { 
        supplier_pn: 'SUP-HW-001', 
        mpn: 'CW-HW-001', 
        cw_cost: 8.25, 
        manufacturer: 'HARDWARE INC' 
      },
      'BOLT-123' => { 
        supplier_pn: 'SUP-BOLT-123', 
        mpn: 'CW-BOLT-123', 
        cw_cost: 3.50, 
        manufacturer: 'FASTENER CO' 
      },
      
      # Motors and electrical
      'MOTOR-123' => { 
        supplier_pn: 'SUP-MOTOR-123', 
        mpn: 'CW-MOTOR-123', 
        cw_cost: 125.00, 
        manufacturer: 'MOTOR SOLUTIONS' 
      },
      'RELAY-456' => { 
        supplier_pn: 'SUP-RELAY-456', 
        mpn: 'CW-RELAY-456', 
        cw_cost: 45.20, 
        manufacturer: 'ELECTRIC CORP' 
      },
      
      # Common test parts
      'TEST-001' => { 
        supplier_pn: 'SUP-TEST-001', 
        mpn: 'CW-TEST-001', 
        cw_cost: 10.00, 
        manufacturer: 'TEST MANUFACTURER' 
      },
      'CROSS-REF-PART' => { 
        supplier_pn: 'SUP-CROSS-001', 
        mpn: 'CW-CROSS-001', 
        cw_cost: 50.00, 
        manufacturer: 'CROSS REF MFG' 
      }
    }
  end
  
  def self.lookup_by_supplier_pn(mfg_partno, include_medical_auto_grades: false)
    return nil if mfg_partno.blank?

    result = mock_crosses[mfg_partno]

    if result
      Rails.logger.info "🎭 [MOCK SQL] Found cross-reference for '#{mfg_partno}' → #{result[:mpn]} (include_medical_auto_grades: #{include_medical_auto_grades})"
    else
      Rails.logger.debug "🎭 [MOCK SQL] No cross-reference found for: #{mfg_partno}"
    end

    result
  rescue => e
    Rails.logger.error "🎭 [MOCK SQL] Error in mock lookup: #{e.message}"
    nil
  end
  
  # Mock data para AML lookups (Total Demand y Min Price)
  def self.mock_aml_data
    {
      total_demand: {
        'PLO-1209841-03-FG' => 572000,
        'MCR01MZPF1500' => 286000,
        'CRCW0402150RFKED' => 286000,
        'RK73H1ETTP2491F' => 1573000,
        'PKG-001' => 50000,
        'HW-001' => 25000,
        'BOLT-123' => 15000,
        'MOTOR-123' => 5000,
        'RELAY-456' => 12000
      },
      
      min_price: {
        'PLO-1209841-03-FG' => 0.05,
        'MCR01MZPF1500' => 0.08,
        'CRCW0402150RFKED' => 0.06,
        'RK73H1ETTP2491F' => 0.12,
        'PKG-001' => 15.50,
        'HW-001' => 2.75,
        'BOLT-123' => 1.25,
        'MOTOR-123' => 85.00,
        'RELAY-456' => 12.50
      }
    }
  end

  # Mock data para opportunity lookup
  def self.lookup_opportunity(opportunity_number)
    return nil if opportunity_number.blank?

    mock_opportunities = {
      '126077' => {
        opportunity_number: '126077',
        opportunity_name: 'Kuiper - CW - AMZ7-KU-NAS1352N04EX4',
        customer: 'JAX',
        probability: 20,
        targeted_quote_deadline: '2026-09-01',
        product_application: 'Cloud',
        bu: 'CEC',
        stage: '2 - Development',
        ear: 0.400,
        site_1: 'MFG North Guad, MEX [SP]',
        bd_owner: 'Rene Keehn',
        sop_date: '2026-09-02'
      },
      '125717' => {
        opportunity_number: '125717',
        opportunity_name: 'AR1.2 and ORV3 Hardware - CW - Cortec Percision - Mitch',
        customer: 'JAX',
        probability: 20,
        targeted_quote_deadline: '2026-02-01',
        product_application: 'Cloud',
        bu: 'CEC',
        stage: '2 - Development',
        ear: 0.000,
        site_1: 'MFG Penang, MYS [P]',
        bd_owner: 'Rene Keehn',
        sop_date: nil
      }
    }

    result = mock_opportunities[opportunity_number.to_s]

    if result
      Rails.logger.info "🎭 [MOCK SQL] Found opportunity '#{opportunity_number}' → #{result[:opportunity_name]}"
    else
      Rails.logger.debug "🎭 [MOCK SQL] No opportunity found for: #{opportunity_number}"
    end

    result
  rescue => e
    Rails.logger.error "🎭 [MOCK SQL] Error in mock opportunity lookup: #{e.message}"
    nil
  end
end