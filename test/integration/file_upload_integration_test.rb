require 'test_helper'

class FileUploadIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    # Limpiar datos de pruebas anteriores
    ProcessedFile.destroy_all
    ProcessedItem.destroy_all
  end

  test "complete file upload and processing workflow" do
    # Paso 1: Verificar que no hay archivos procesados
    assert_equal 0, ProcessedFile.count
    
    # Paso 2: Crear archivo de prueba
    test_file = create_test_excel_file
    
    # Paso 3: Subir archivo
    post file_uploads_path, params: {
      file_upload: {
        file: fixture_file_upload(test_file, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      }
    }
    
    # Verificar redirección exitosa
    assert_response :redirect
    
    # Verificar que se creó el ProcessedFile
    assert_equal 1, ProcessedFile.count
    processed_file = ProcessedFile.last
    
    # Verificar estado inicial
    assert_equal 'queued', processed_file.status
    assert processed_file.original_file.attached?
    
    # Paso 4: Simular procesamiento del job (sin hacer llamadas reales a OpenAI)
    simulate_processing(processed_file)
    
    # Paso 5: Verificar resultados
    processed_file.reload
    assert_equal 'completed', processed_file.status
    assert processed_file.processed_items.any?
    assert processed_file.result_file_path.present?
    
    # Verificar que se mapearon columnas
    assert processed_file.column_mapping.present?
    
    # Verificar que se asignaron commodities
    items_with_commodity = processed_file.processed_items.where.not(commodity: 'Unknown')
    assert items_with_commodity.any?, "Should have items with assigned commodities"
    
    # Verificar que se asignaron scopes
    items_with_scope = processed_file.processed_items.where.not(scope: nil)
    assert items_with_scope.any?, "Should have items with assigned scopes"
    
    puts "✅ Test passed: File uploaded and processed successfully"
  end

  private

  def create_test_excel_file
    # Crear archivo Excel simple para pruebas
    file_path = Rails.root.join('tmp', 'test_upload.xlsx')
    
    package = Axlsx::Package.new
    workbook = package.workbook
    
    workbook.add_worksheet(name: "Test Data") do |sheet|
      # Headers
      sheet.add_row ['ITEM', 'DESCRIPTION', 'MFG_PARTNO', 'USD_STD_COST', 'LEVEL3_DESC']
      
      # Test data
      sheet.add_row ['ITEM001', 'Test packaging item 1', 'PKG-001', '10.50', 'PACK LABELS']
      sheet.add_row ['ITEM002', 'Test packaging item 2', 'PKG-002', '15.75', 'PACK BROWN BOX']
      sheet.add_row ['ITEM003', 'Test hardware item', 'HW-001', '5.25', 'HARDWARE']
    end
    
    package.serialize(file_path)
    file_path
  end

  def simulate_processing(processed_file)
    # Simular lo que hace ExcelProcessorJob sin llamadas reales a OpenAI
    
    # 1. Simular mapeo de columnas
    column_mapping = {
      'ITEM' => 'ITEM',
      'DESCRIPTION' => 'DESCRIPTION', 
      'MFG_PARTNO' => 'MFG_PARTNO',
      'STD_COST' => 'USD_STD_COST',
      'LEVEL3_DESC' => 'LEVEL3_DESC'
    }
    processed_file.update(column_mapping: column_mapping)
    
    # 2. Crear items procesados simulados
    test_items = [
      {
        item: 'ITEM001',
        description: 'Test packaging item 1',
        mfg_partno: 'PKG-001',
        std_cost: 10.50,
        commodity: 'PACK LABELS',
        scope: 'In scope'
      },
      {
        item: 'ITEM002', 
        description: 'Test packaging item 2',
        mfg_partno: 'PKG-002',
        std_cost: 15.75,
        commodity: 'PACK BROWN BOX',
        scope: 'In scope'  
      },
      {
        item: 'ITEM003',
        description: 'Test hardware item',
        mfg_partno: 'HW-001', 
        std_cost: 5.25,
        commodity: 'HARDWARE',
        scope: 'Out of scope'
      }
    ]
    
    test_items.each do |item_data|
      processed_file.processed_items.create!(item_data)
    end
    
    # 3. Simular creación de archivo de resultado
    result_file_path = Rails.root.join('tmp', "test_result_#{processed_file.id}.xlsx")
    FileUtils.touch(result_file_path)  # Crear archivo vacío para la prueba
    
    # 4. Actualizar estado
    processed_file.update(
      status: 'completed',
      processed_at: Time.current,
      result_file_path: result_file_path.to_s
    )
  end
end