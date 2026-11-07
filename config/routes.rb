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

  # Admin Area
  namespace :admin do
    root to: 'dashboard#show'
    resource :settings, only: %i[show update]
    resources :vehicle_fields, except: :show do
      patch :move, on: :member
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
