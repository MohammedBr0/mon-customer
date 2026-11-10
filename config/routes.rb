# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
  devise_scope :user do
    delete 'sign_out', to: 'devise/sessions#destroy', as: :destroy_user_session
  end

  # Pages Neon Auth redirects to during the OpenID Connect authorization flow
  get 'neon_auth/login', to: 'neon_auth#login', as: :neon_auth_login
  get 'neon_auth/consent', to: 'neon_auth#consent', as: :neon_auth_consent

  root to: 'pages#home'

  resources :conversations, only: %i[show new create update index] do
    get :unread, on: :collection
  end

  resources :feedbacks, only: %i[show new create edit update destroy index]

  get 'maps/geocode', to: 'maps#geocode'
  get 'maps/route', to: 'maps#route'

  resources :city_commutes, only: %i[index new create]

  resources :itineraries, only: %i[show new create edit update destroy index search] do
    post :search, on: :collection
    patch :cancel, on: :member
    resources :build
    resources :bookings, only: :create
  end

  resources :bookings, only: :index do
    member do
      patch :confirm
      patch :decline
      patch :cancel
      patch :skip_date
    end
    resources :reviews, only: %i[new create]
  end

  resources :ride_alerts, only: %i[index create destroy]
  resources :reports, only: %i[new create]

  resources :users, only: %i[show update destroy] do
    get :itineraries, on: :member
  end

  # JSON API for the mobile app
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resource :config, only: :show, controller: :config
      post 'auth/sign_in', to: 'auth#sign_in'
      post 'auth/sign_up', to: 'auth#sign_up'
      post 'auth/send_code', to: 'auth#send_code'
      delete 'auth/sign_out', to: 'auth#sign_out'
      resource :me, only: %i[show update destroy], controller: :me do
        put :payment_methods
        post :identity
      end
      resources :itineraries, only: %i[index show create update] do
        get :mine, on: :collection
        patch :cancel, on: :member
        resources :bookings, only: :create
      end
      resources :bookings, only: :index do
        member do
          patch :confirm
          patch :decline
          patch :cancel
          patch :skip_date
        end
        resources :reviews, only: :create
      end
      resources :conversations, only: %i[index show create] do
        post :message, on: :member
      end
      resources :notifications, only: :index do
        collection { post :read_all }
        patch :read, on: :member
      end
      get 'maps/search', to: 'maps#search'
      get 'maps/reverse', to: 'maps#reverse'
      get 'maps/route', to: 'maps#route'
      resources :ride_alerts, only: %i[index create destroy]
      resources :reports, only: :create
    end
  end

  # Admin Area
  namespace :admin do
    root to: 'dashboard#show'
    resource :settings, only: %i[show update]
    resources :vehicle_fields, except: :show do
      patch :move, on: :member
    end
    resources :payment_methods, except: :show
    resources :identity_documents, only: %i[index show] do
      get :image, on: :member
      patch :approve, on: :member
      patch :reject, on: :member
    end
    resources :popular_routes, except: :show do
      patch :move, on: :member
    end
    resources :users, only: %i[index show] do
      get :login_as, on: :member
      post :ban, on: :member
      post :unban, on: :member
      post :verify, on: :member
      post :unverify, on: :member
      patch :set_role, on: :member
    end
    resources :itineraries, only: :index do
      patch :cancel, on: :member
    end
    resources :bookings, only: :index do
      patch :cancel, on: :member
    end
    resources :reports, only: %i[index show] do
      patch :resolve, on: :member
    end
    resources :reviews, only: :index do
      patch :hide, on: :member
      patch :unhide, on: :member
    end
    resources :audit_logs, only: :index
  end

  # Root route aliases
  get :dashboard, to: 'users#dashboard'
  get :settings, to: 'users#settings'
  get :banned, to: 'users#banned'

  get :about, to: 'pages#about'
  get :how_it_works, to: 'pages#how_it_works'
  get :privacy, to: 'pages#privacy'
  get :terms, to: 'pages#terms'
  post :report_uri, to: 'pages#report_uri'
end
