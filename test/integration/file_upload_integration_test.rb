require 'test_helper'

class FileUploadIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    # Limpiar datos de pruebas anteriores
    ProcessedFile.destroy_all
    ProcessedItem.destroy_all
    CommodityReference.destroy_all
    ManufacturerMapping.destroy_all
    
    # Crear datos de prueba necesarios
    create_test_data
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
    
    # Paso 4: Procesar archivo con funcionalidad real
    process_file_real(processed_file)
    
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
      sheet.add_row ['ITEM001', 'packaging labels adhesive premium quality', 'PKG-001', '10.50', 'PACK LABELS']
      sheet.add_row ['ITEM002', 'brown cardboard shipping box medium size', 'PKG-002', '15.75', 'PACK BROWN BOX']
      sheet.add_row ['ITEM003', 'stainless steel bolt hardware fastener', 'HW-001', '5.25', 'HARDWARE']
    end
    
    package.serialize(file_path)
    file_path
  end

  def create_test_data
    # Crear commodity references necesarias
    CommodityReference.create!([
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
        level3_desc: "PACK BROWN BOX",
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
  
  def process_file_real(processed_file)
    skip "Skipping real processing - set RUN_REAL_TESTS=1 to enable" unless ENV['RUN_REAL_TESTS']
    
    # Usar el servicio real de procesamiento
    service = ExcelProcessorService.new(processed_file)
    
    # Obtener el archivo attachado
    attached_file = processed_file.original_file
    
    # Procesar con el servicio real
    result = service.process_upload(attached_file)
    
    assert result[:success], "Processing should succeed"
    
    puts "✅ Real processing completed successfully"
    puts "📊 Processed items: #{processed_file.processed_items.count}"
    puts "🎯 Classified items: #{processed_file.processed_items.where.not(commodity: 'Unknown').count}"
  end
end