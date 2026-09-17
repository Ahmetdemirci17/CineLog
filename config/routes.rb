Rails.application.routes.draw do
  devise_for :users

  root "movies#index"

  resources :movies, only: [:index, :show]
  resources :tv_shows, only: [:show], path: "tv"
  get "search", to: "movies#search", as: :search
  get "search/suggestions", to: "movies#suggestions", as: :search_suggestions
  resources :genres, only: [:index, :show], path: "katalog"
  resources :people, only: [:show], path: "oyuncu"

  resources :watchlists, only: [:index, :create, :update, :destroy]

  resources :community_posts, path: "community" do
    resources :community_replies, only: [:create, :destroy], path: "replies"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
