require 'rails_helper'

RSpec.describe OpenaiService, type: :service do
  describe '.get_embeddings' do
    it 'returns embeddings for the given texts' do
      # Mock client para no llamar a la API real
      client_mock = instance_double(OpenAI::Client)
      allow(OpenAI::Client).to receive(:new).and_return(client_mock)
      
      # Respuesta simulada de OpenAI
      mock_response = {
        "data" => [
          { "embedding" => [0.1, 0.2, 0.3] },
          { "embedding" => [0.4, 0.5, 0.6] }
        ]
      }
      
      # Configurar expectativa de llamada
      expect(client_mock).to receive(:embeddings).with(
        parameters: {
          model: OpenaiService::EMBEDDING_MODEL,
          input: ["hello", "world"]
        }
      ).and_return(mock_response)
      
      # Llamar al método
      result = OpenaiService.get_embeddings(["hello", "world"])
      
      # Verificar el resultado
      expect(result).to eq([[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]])
    end
    
    it 'returns an empty array when input is empty' do
      result = OpenaiService.get_embeddings([])
      expect(result).to eq([])
    end
    
    it 'handles API errors gracefully' do
      client_mock = instance_double(OpenAI::Client)
      allow(OpenAI::Client).to receive(:new).and_return(client_mock)
      
      # Simular error en la API
      expect(client_mock).to receive(:embeddings).and_raise(StandardError.new("API Error"))
      
      # Capturar error de log
      expect(Rails.logger).to receive(:error).with(/OpenAI API error: API Error/)
      
      # Llamar al método
      result = OpenaiService.get_embeddings(["hello"])
      
      # Verificar que devuelve array vacío en caso de error
      expect(result).to eq([])
    end
  end
  
  describe '.identify_columns' do
    it 'identifies columns based on sample rows' do
      # Similar al test anterior, mockear respuesta de OpenAI
      client_mock = instance_double(OpenAI::Client)
      allow(OpenAI::Client).to receive(:new).and_return(client_mock)
      
      # Datos de muestra
      sample_rows = [
        { "Part ID" => "SG123456", "SKU Number" => "CAP-001" },
        { "Part ID" => "SG234567", "SKU Number" => "RES-002" }
      ]
      
      target_columns = ["SUGAR_ID", "ITEM"]
      
      # Respuesta simulada
      mock_response = {
        "choices" => [
          {
            "message" => {
              "content" => '{"SUGAR_ID": "Part ID", "ITEM": "SKU Number"}'
            }
          }
        ]
      }
      
      # Expectativa
      expect(client_mock).to receive(:chat).and_return(mock_response)
      
      # Llamar al método
      result = OpenaiService.identify_columns(sample_rows, target_columns)
      
      # Verificar el resultado
      expect(result).to eq({"SUGAR_ID" => "Part ID", "ITEM" => "SKU Number"})
    end
  end
end