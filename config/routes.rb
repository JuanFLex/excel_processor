Rails.application.routes.draw do
  resources :file_uploads, only: [:index, :new, :create, :show] do
  member do
    get :download
    get :status
  end
end
end
