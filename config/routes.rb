Rails.application.routes.draw do
  devise_for :users
  # Definir la ruta raíz
  root 'file_uploads#index'

  namespace :admin do
    resources :users
  end
  
  resources :file_uploads, only: [:index, :new, :create, :show] do
    member do
      get :download
      get :status
      get :remap
      patch :reprocess
    end
    
    collection do
      get :download_sample
    end
  end
  
  resources :commodity_references, only: [:index, :edit, :update] do
    collection do
      get :upload
      post :process_upload
    end
  end
end