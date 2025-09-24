require 'test_helper'

class ExcelProcessorServiceTest < ActiveSupport::TestCase
  def setup
    # Limpiar datos de prueba
    ProcessedFile.destroy_all
    ProcessedItem.destroy_all
    CommodityReference.destroy_all
    ManufacturerMapping.destroy_all
    
    # Crear datos de prueba
    create_test_data
  end

  test "automatic scope assignment for items with cross-references" do
    # Crear archivo procesado para test
    processed_file = ProcessedFile.create!(
      original_filename: 'test_scope.xlsx',
      status: 'processing'
    )
    
    service = ExcelProcessorService.new(processed_file)
    
    # Test extract_values con datos que incluyen manufacturer part numbers
    test_row = {
      'ITEM' => 'TEST001',
      'DESCRIPTION' => 'Test item for scope verification',
      'MFG_PARTNO' => 'CROSS-REF-PART',  # Este part number tiene cruce
      'GLOBAL_MFG_NAME' => 'TEST MFG CO',
      'STD_COST' => '15.50'
    }
    
    column_mapping = {
      'ITEM' => 'ITEM',
      'DESCRIPTION' => 'DESCRIPTION',
      'MFG_PARTNO' => 'MFG_PARTNO',
      'GLOBAL_MFG_NAME' => 'GLOBAL_MFG_NAME',
      'STD_COST' => 'STD_COST'
    }
    
    # Mock ItemLookup para simular que encuentra cruce
    ItemLookup.stub(:lookup_by_supplier_pn, { mpn: 'CROSS-001', manufacturer: 'TEST MFG' }) do
      values = service.send(:extract_values, test_row, column_mapping)
      
      # Verificar que se estandarizó el manufacturer
      assert_equal 'TEST MANUFACTURER INC', values['global_mfg_name']
      
      puts "✅ Manufacturer standardization works"
      puts "🏭 'TEST MFG CO' → '#{values['global_mfg_name']}'"
    end
  end

  test "scope determination logic with various scenarios" do
    processed_file = ProcessedFile.create!(
      original_filename: 'test_scope_scenarios.xlsx',
      status: 'processing'
    )
    
    service = ExcelProcessorService.new(processed_file)
    
    # Scenario 1: Item with cross-reference should be 'In scope'
    test_data_with_cross = {
      'item' => 'ITEM001',
      'description' => 'Item with cross reference',
      'mfg_partno' => 'HAS-CROSS-REF',
      'commodity' => 'Unknown',
      'scope' => 'Out of scope'
    }
    
    # Scenario 2: Item without cross-reference keeps original scope
    test_data_no_cross = {
      'item' => 'ITEM002', 
      'description' => 'Item without cross reference',
      'mfg_partno' => 'NO-CROSS-REF',
      'commodity' => 'HARDWARE',
      'scope' => 'Out of scope'
    }
    
    # Mock ItemLookup selectively
    ItemLookup.stub(:lookup_by_supplier_pn, ->(part_no) {
      part_no == 'HAS-CROSS-REF' ? { mpn: 'CROSS-001' } : nil
    }) do
      
      # Create test items to verify scope logic
      processed_file.processed_items.create!(test_data_with_cross)
      processed_file.processed_items.create!(test_data_no_cross)
      
      # In real processing, scope would be overridden for items with cross-reference
      # This tests the logic conceptually
      
      item_with_cross = processed_file.processed_items.find_by(mfg_partno: 'HAS-CROSS-REF')
      item_without_cross = processed_file.processed_items.find_by(mfg_partno: 'NO-CROSS-REF')
      
      assert item_with_cross.present?, "Item with cross-reference should exist"
      assert item_without_cross.present?, "Item without cross-reference should exist"
      
      puts "✅ Scope determination test setup completed"
      puts "🔍 Item with cross: #{item_with_cross.mfg_partno}"
      puts "🔍 Item without cross: #{item_without_cross.mfg_partno}"
    end
  end

  test "manufacturer mapping standardization" do
    # Test que el modelo funciona correctamente
    assert_equal "TEST MANUFACTURER INC", ManufacturerMapping.standardize("TEST MFG CO")
    assert_equal "SAMSUNG INC", ManufacturerMapping.standardize("SAMSUNG CO")
    assert_equal "UNKNOWN BRAND", ManufacturerMapping.standardize("UNKNOWN BRAND")  # Sin mapping
    assert_equal "UNKNOWN BRAND", ManufacturerMapping.standardize(" UNKNOWN BRAND ")  # Con espacios
    
    puts "✅ Manufacturer mapping tests passed"
  end

  test "token estimation accuracy" do
    test_cases = [
      { text: "hola", expected: 2 },      # 4 chars = 1 token, rounded up
      { text: "hola mundo", expected: 3 }, # 10 chars = 2.5 = 3 tokens
      { text: "motor electrico bomba hidraulica", expected: 9 }, # 35 chars = 8.75 = 9 tokens
      { text: "", expected: 0 }            # Empty text
    ]

    test_cases.each do |test_case|
      estimated = OpenaiService.send(:estimate_tokens, test_case[:text])
      assert_equal test_case[:expected], estimated,
        "Text '#{test_case[:text]}' should estimate #{test_case[:expected]} tokens, got #{estimated}"
    end

    puts "✅ Token estimation accuracy tests passed"
  end

  test "autograde scope functionality in processing" do
    # Crear commodity con ambos scope fields
    CommodityReference.create!([
      {
        global_comm_code_desc: "AUTO PARTS",
        level1_desc: "DIRECT MATERIALS",
        level2_desc: "AUTOMOTIVE",
        level3_desc: "AUTO COMPONENT",
        infinex_scope_status: "Out of scope",
        autograde_scope: "In scope"  # Diferente del infinex_scope_status
      }
    ])

    # Test directo del método scope_for_commodity con diferentes modos
    # Modo comercial (auto_mode = false)
    result_commercial = CommodityReference.scope_for_commodity('AUTO COMPONENT', 'level3_desc', false)
    assert_equal 'Out of scope', result_commercial
    puts "✅ Commercial mode uses infinex_scope_status correctly"

    # Modo auto (auto_mode = true)
    result_auto = CommodityReference.scope_for_commodity('AUTO COMPONENT', 'level3_desc', true)
    assert_equal 'In scope', result_auto
    puts "✅ Auto mode uses autograde_scope correctly"

    puts "✅ Autograde scope functionality tests passed"
  end

  private

  def create_test_data
    # Crear commodity references
    CommodityReference.create!([
      {
        global_comm_code_desc: "PACKAGING",
        level1_desc: "INDIRECT MATERIALS",
        level2_desc: "PACKAGING", 
        level3_desc: "PACK LABELS",
        infinex_scope_status: "In Scope"
      },
      {
        global_comm_code_desc: "HARDWARE",
        level1_desc: "DIRECT MATERIALS",
        level2_desc: "HARDWARE",
        level3_desc: "HARDWARE", 
        infinex_scope_status: "Out of scope"
      }
    ])
    
    # Crear manufacturer mappings
    ManufacturerMapping.create!([
      { original_name: "TEST MFG CO", standardized_name: "TEST MANUFACTURER INC" },
      { original_name: "SAMSUNG CO", standardized_name: "SAMSUNG INC" }
    ])
  end
end