Rails.application.routes.draw do
  root "home#index"

  get "registration", to: "registrations#new", as: :new_registration
  post "registration", to: "registrations#create", as: :registration
  get "email/confirmation", to: "email_confirmations#show", as: :email_confirmation

  post "login", to: "login_challenges#create", as: :login
  get "login/verify", to: "login_challenges#new", as: :verify_login
  post "login/verify", to: "login_challenges#verify"
  delete "session", to: "sessions#destroy", as: :session

  resource :profile, only: %i[show edit update]
  resources :personalities, only: %i[index new create show edit update] do
    patch :archive, on: :member
    resources :memories, only: %i[index update destroy] do
      patch :approve, on: :member
      patch :settings, on: :collection
      delete :clear, on: :collection
    end
    resources :versions, only: :index, controller: "personality_versions" do
      get :compare, on: :collection
      post :rollback, on: :member
    end
    resources :conversation_threads, path: "threads", only: %i[index new create show] do
      patch :archive, on: :member
      resources :messages, only: :create
      resources :generation_runs, only: [] do
        get :stream, on: :member
        post :stop, on: :member
        post :retry, on: :member
      end
    end
  end


  post "locale/:locale", to: "locales#update", as: :locale

  get "up" => "rails/health#show", as: :rails_health_check
  get "operations/health" => "operations/health#show", as: :operations_health
  mount Sidekiq::Web => "/operations/sidekiq", as: :operations_sidekiq
end
