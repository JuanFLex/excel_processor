class MockItemLookup
  # Mock para ItemLookup cuando no hay acceso a SQL Server
  
  def self.lookup_by_supplier_pn(mfg_partno)
    return nil if mfg_partno.blank?
    
    # Base de datos falsa de part numbers con cruces para testing
    mock_crosses = {
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
    
    result = mock_crosses[mfg_partno]
    
    if result
      Rails.logger.info "🎭 [MOCK SQL] Found cross-reference for '#{mfg_partno}' → #{result[:mpn]}"
    else  
      Rails.logger.debug "🎭 [MOCK SQL] No cross-reference found for: #{mfg_partno}"
    end
    
    result
  rescue => e
    Rails.logger.error "🎭 [MOCK SQL] Error in mock lookup: #{e.message}"
    nil
  end
end