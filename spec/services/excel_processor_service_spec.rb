require 'rails_helper'

RSpec.describe ExcelProcessorService, type: :service do
  describe '#process_upload' do
    let(:processed_file) { create(:processed_file) }
    let(:service) { ExcelProcessorService.new(processed_file) }
    
    it 'processes an Excel file and creates processed items' do
      # Este test es complejo y requeriría crear un archivo Excel real
      # Para simplificar, podemos mockear las llamadas internas
      
      # Mockear el método open_spreadsheet
      allow(service).to receive(:open_spreadsheet).and_return(
        double(
          row: -> (row_num) { row_num == 1 ? ["Part ID", "SKU Number"] : ["SG123456", "CAP-001"] },
          last_row: 2
        )
      )
      
      # Mockear la identificación de columnas
      allow(OpenaiService).to receive(:identify_columns).and_return({
        "SUGAR_ID" => "Part ID",
        "ITEM" => "SKU Number"
      })
      
      # Mockear la obtención de embeddings
      allow(OpenaiService).to receive(:get_embedding_for_text).and_return([0.1, 0.2, 0.3])
      
      # Mockear la búsqueda de commodity similar
      allow_any_instance_of(CommodityReference).to receive(:find_most_similar).and_return([
        double(level2_desc: "Capacitors", infinex_scope_status: "In Scope")
      ])
      
      # Mockear la generación del archivo de salida
      allow(service).to receive(:generate_output_file)
      
      # Crear un archivo falso para pasar al método
      file = double(
        original_filename: "test.xlsx",
        path: "/tmp/test.xlsx"
      )
      
      # Llamar al método
      result = service.process_upload(file)
      
      # Verificar resultado
      expect(result[:success]).to be true
      expect(processed_file.reload.status).to eq("completed")
    end
  end
end