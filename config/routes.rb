Rails.application.routes.draw do
  devise_for :users
  # Definir la ruta raíz
  root 'file_uploads#index'

  namespace :admin do
    resources :users
  end
  
  resources :file_uploads, only: [:index, :new, :create, :show, :destroy] do
    member do
      get :download
      get :status
      get :remap
      patch :reprocess
      post :export_preview
      post :export_filtered
      patch :approve_mapping
      patch :update_mapping
    end

    collection do
      post :lookup_opportunity
    end
  end
  
  resources :commodity_references, only: [:index, :edit, :update] do
    collection do
      get :upload
      post :process_upload
      get :search  # Para autocompletado JSON
    end
  end
end