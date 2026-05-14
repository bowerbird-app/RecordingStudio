Rails.application.routes.draw do
  devise_for :users

  mount FlatPack::Engine => "/flatpack", as: "flatpack"
  mount RecordingStudio::Engine, at: "/recording_studio"

  resources :folders, param: :recording_id, only: [ :index, :show ]
  resources :workspaces, only: [ :index, :show, :new, :create ] do
    resources :pages, controller: :pages, param: :recording_id, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
  end
  get "config", to: "config#index", as: :recording_studio_config
  get :tree, to: "tree#index"
  resources :events, only: [ :index ]
  get :methods, to: "methods#index"
  resources :recordings, only: [ :index, :show ] do
    post :log_event, on: :member
    post :revert, on: :member
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
end
