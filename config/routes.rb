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

  post "locale/:locale", to: "locales#update", as: :locale

  get "up" => "rails/health#show", as: :rails_health_check
end
