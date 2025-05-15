require 'rails_helper'

RSpec.describe FileUploadsController, type: :controller do
  describe 'GET #index' do
    it 'returns http success' do
      get :index
      expect(response).to have_http_status(:success)
    end
    
    it 'assigns @processed_files' do
      processed_file = create(:processed_file)
      get :index
      expect(assigns(:processed_files)).to include(processed_file)
    end
  end
  
  describe 'GET #new' do
    it 'returns http success' do
      get :new
      expect(response).to have_http_status(:success)
    end
    
    it 'assigns a new @processed_file' do
      get :new
      expect(assigns(:processed_file)).to be_a_new(ProcessedFile)
    end
  end
  
  describe 'POST #create' do
    let(:file) { fixture_file_upload('spec/fixtures/test_inventory.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }
    
    it 'creates a new ProcessedFile' do
      # Mockear ExcelProcessorJob para que no se ejecute realmente
      allow(ExcelProcessorJob).to receive(:perform_later)
      
      expect {
        post :create, params: { file_upload: { file: file } }
      }.to change(ProcessedFile, :count).by(1)
    end
    
    it 'redirects to the created file_upload' do
      # Mockear ExcelProcessorJob para que no se ejecute realmente
      allow(ExcelProcessorJob).to receive(:perform_later)
      
      post :create, params: { file_upload: { file: file } }
      expect(response).to redirect_to(file_upload_path(ProcessedFile.last))
    end
  end
  
  describe 'GET #show' do
    let(:processed_file) { create(:processed_file) }
    
    it 'returns http success' do
      get :show, params: { id: processed_file.id }
      expect(response).to have_http_status(:success)
    end
    
    it 'assigns the requested @processed_file' do
      get :show, params: { id: processed_file.id }
      expect(assigns(:processed_file)).to eq(processed_file)
    end
  end
  
  describe 'GET #download' do
    context 'when file is completed' do
      let(:processed_file) { create(:completed_processed_file) }
      
      before do
        # Crear un archivo temporal para simular el archivo de resultado
        File.write(processed_file.result_file_path, "test content")
      end
      
      after do
        # Limpiar archivo temporal
        File.delete(processed_file.result_file_path) if File.exist?(processed_file.result_file_path)
      end
      
      it 'sends the file' do
        expect(controller).to receive(:send_file).with(
          processed_file.result_file_path,
          hash_including(
            type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            disposition: 'attachment'
          )
        ).and_call_original
        
        get :download, params: { id: processed_file.id }
      end
    end
    
    context 'when file is not completed' do
      let(:processed_file) { create(:processing_processed_file) }
      
      it 'redirects to the file_upload with an alert' do
        get :download, params: { id: processed_file.id }
        expect(response).to redirect_to(file_upload_path(processed_file))
        expect(flash[:alert]).to be_present
      end
    end
  end
  
  describe 'GET #status' do
    let(:processed_file) { create(:processed_file, status: 'processing') }
    
    it 'returns the status as JSON' do
      get :status, params: { id: processed_file.id }
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['status']).to eq('processing')
    end
  end
end