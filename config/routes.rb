Rails.application.routes.draw do
  # Definir la ruta raíz
  root 'file_uploads#index'
  
  resources :file_uploads, only: [:index, :new, :create, :show] do
    member do
      get :download
      get :status
    end
    
    collection do
      get :download_sample
    end
  end
  
  resources :commodity_references, only: [:index] do
    collection do
      get :upload
      post :process_upload
    end
  end
end