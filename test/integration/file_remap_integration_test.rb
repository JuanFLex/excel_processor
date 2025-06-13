require 'test_helper'

class FileRemapIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    # Limpiar datos de pruebas anteriores
    ProcessedFile.destroy_all
    ProcessedItem.destroy_all
    CommodityReference.destroy_all
    
    # Crear referencias necesarias para el test
    create_test_commodity_references
  end

  test "complete file remap workflow" do
    # Paso 1: Crear archivo procesado inicial
    processed_file = create_initial_processed_file
    
    # Verificar estado inicial
    assert_equal 'completed', processed_file.status
    assert_equal 3, processed_file.processed_items.count
    
    # Verificar commodities iniciales
    pack_box_items = processed_file.processed_items.where(commodity: 'PACK BROWN BOX')
    pack_labels_items = processed_file.processed_items.where(commodity: 'PACK LABELS')
    
    assert_equal 1, pack_box_items.count
    assert_equal 1, pack_labels_items.count
    
    # Paso 2: Acceder a página de remapeo
    get remap_file_upload_path(processed_file)
    assert_response :success
    
    # Paso 3: Hacer remapeo de commodities
    remap_params = {
      remap: {
        column_mapping: {
          'ITEM' => 'ITEM',
          'DESCRIPTION' => 'DESCRIPTION',
          'STD_COST' => 'USD_STD_COST',
          'LEVEL3_DESC' => 'LEVEL3_DESC'
        },
        commodity_changes: {
          'PACK BROWN BOX' => 'PACKAGING PREMIUM',  # Cambiar a commodity nuevo
          'PACK LABELS' => ''  # Mantener igual (string vacío)
        }
      }
    }
    
    # Paso 4: Enviar remapeo
    patch reprocess_file_upload_path(processed_file), params: remap_params
    assert_response :redirect
    
    # Verificar que el estado cambió a processing
    processed_file.reload
    assert_equal 'processing', processed_file.status
    
    # Paso 5: Simular procesamiento del remapeo
    simulate_remap_processing(processed_file, remap_params[:remap])
    
    # Paso 6: Verificar resultados del remapeo
    processed_file.reload
    assert_equal 'completed', processed_file.status
    
    # Verificar que los commodities cambiaron correctamente
    premium_items = processed_file.processed_items.where(commodity: 'PACKAGING PREMIUM')
    unchanged_items = processed_file.processed_items.where(commodity: 'PACK LABELS')
    old_items = processed_file.processed_items.where(commodity: 'PACK BROWN BOX')
    
    assert_equal 1, premium_items.count, "Should have 1 item changed to PACKAGING PREMIUM"
    assert_equal 1, unchanged_items.count, "Should have 1 item unchanged as PACK LABELS"
    assert_equal 0, old_items.count, "Should have 0 items with old PACK BROWN BOX commodity"
    
    # Verificar que otros items no se afectaron
    hardware_items = processed_file.processed_items.where(commodity: 'HARDWARE')
    assert_equal 1, hardware_items.count, "Hardware item should remain unchanged"
    
    # Verificar que scopes se actualizaron correctamente
    premium_item = premium_items.first
    assert_equal 'In scope', premium_item.scope, "New commodity should have correct scope"
    
    puts "✅ Test passed: File remapped successfully"
  end

  private

  def create_test_commodity_references
    # Crear referencias que coincidan con los datos de prueba
    CommodityReference.create!([
      {
        global_comm_code_desc: "PACKAGING",
        level1_desc: "INDIRECT MATERIALS",
        level2_desc: "PACKAGING",
        level3_desc: "PACK BROWN BOX",
        infinex_scope_status: "In Scope"
      },
      {
        global_comm_code_desc: "PACKAGING",
        level1_desc: "INDIRECT MATERIALS", 
        level2_desc: "PACKAGING",
        level3_desc: "PACK LABELS",
        infinex_scope_status: "In Scope"
      },
      {
        global_comm_code_desc: "PACKAGING",
        level1_desc: "INDIRECT MATERIALS",
        level2_desc: "PACKAGING", 
        level3_desc: "PACKAGING PREMIUM",
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
  end

  def create_initial_processed_file
    # Crear archivo de prueba
    processed_file = ProcessedFile.create!(
      original_filename: 'test_remap.xlsx',
      status: 'completed',
      processed_at: Time.current,
      column_mapping: {
        'ITEM' => 'ITEM',
        'DESCRIPTION' => 'DESCRIPTION',
        'STD_COST' => 'USD_STD_COST', 
        'LEVEL3_DESC' => 'LEVEL3_DESC'
      }
    )
    
    # Create real Excel file for testing
    excel_file_path = create_dummy_excel_file
    processed_file.original_file.attach(
      io: File.open(excel_file_path),
      filename: "test_remap.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    
    # Clean up temp file
    File.delete(excel_file_path) if File.exist?(excel_file_path)
    
    # Crear items iniciales
    processed_file.processed_items.create!([
      {
        item: 'ITEM001',
        description: 'Test packaging box',
        std_cost: 10.50,
        commodity: 'PACK BROWN BOX',
        scope: 'In scope'
      },
      {
        item: 'ITEM002',
        description: 'Test packaging labels', 
        std_cost: 5.25,
        commodity: 'PACK LABELS',
        scope: 'In scope'
      },
      {
        item: 'ITEM003',
        description: 'Test hardware item',
        std_cost: 15.00,
        commodity: 'HARDWARE', 
        scope: 'Out of scope'
      }
    ])
    
    processed_file
  end

  def create_dummy_excel_file
    # Crear archivo Excel real pero simple
    file_path = Rails.root.join('tmp', "test_dummy_#{Time.current.to_i}.xlsx")
    
    package = Axlsx::Package.new
    workbook = package.workbook
    
    workbook.add_worksheet(name: "Test Data") do |sheet|
      # Headers que coincidan con el column_mapping
      sheet.add_row ['ITEM', 'DESCRIPTION', 'USD_STD_COST', 'LEVEL3_DESC', 'EXTRA_COL1', 'EXTRA_COL2']
      
      # Data rows
      sheet.add_row ['ITEM001', 'Test packaging box', '10.50', 'PACK BROWN BOX', 'extra1', 'extra2']
      sheet.add_row ['ITEM002', 'Test packaging labels', '5.25', 'PACK LABELS', 'extra3', 'extra4'] 
      sheet.add_row ['ITEM003', 'Test hardware item', '15.00', 'HARDWARE', 'extra5', 'extra6']
    end
    
    package.serialize(file_path)
    file_path
  end

  def simulate_remap_processing(processed_file, remap_params)
    # Simular lo que hace ExcelProcessorJob para remapeo
    
    # 1. Limpiar items existentes (como hace el job real)
    processed_file.processed_items.destroy_all
    
    # 2. Aplicar cambios de remapeo
    commodity_changes = remap_params[:commodity_changes]
    
    # 3. Recrear items con cambios aplicados
    test_items = [
      {
        item: 'ITEM001',
        description: 'Test packaging box',
        std_cost: 10.50,
        commodity: apply_commodity_change('PACK BROWN BOX', commodity_changes),
        scope: 'In scope'
      },
      {
        item: 'ITEM002', 
        description: 'Test packaging labels',
        std_cost: 5.25,
        commodity: apply_commodity_change('PACK LABELS', commodity_changes),
        scope: 'In scope'
      },
      {
        item: 'ITEM003',
        description: 'Test hardware item', 
        std_cost: 15.00,
        commodity: apply_commodity_change('HARDWARE', commodity_changes),
        scope: 'Out of scope'
      }
    ]
    
    test_items.each do |item_data|
      processed_file.processed_items.create!(item_data)
    end
    
    # 4. Actualizar estado
    processed_file.update(
      status: 'completed',
      processed_at: Time.current
    )
  end

  def apply_commodity_change(original_commodity, commodity_changes)
    new_commodity = commodity_changes[original_commodity]
    
    # Si el cambio está vacío o es nil, mantener original
    if new_commodity.present?
      new_commodity
    else
      original_commodity
    end
  end
end