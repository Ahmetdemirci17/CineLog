Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }

  root "movies#index"

  resources :movies, only: [:index, :show]
  resources :tv_shows, only: [:index, :show], path: "tv"
  get "search", to: "movies#search", as: :search
  get "search/suggestions", to: "movies#suggestions", as: :search_suggestions
  resources :genres, only: [:index, :show], path: "katalog"
  resources :people, only: [:show], path: "oyuncu"

  resources :watchlists, only: [:index, :create, :update, :destroy]

  resources :community_posts, path: "community" do
    resources :community_replies, only: [:create, :destroy], path: "replies"
  end

  namespace :admin do
    root to: "dashboard#index"
    resources :users, only: [:index, :show, :destroy] do
      member do
        patch :toggle_admin
      end
    end
    resources :community_posts, only: [:index, :show, :destroy] do
      resources :community_replies, only: [:destroy]
    end
    resources :watchlists, only: [:index, :destroy]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
