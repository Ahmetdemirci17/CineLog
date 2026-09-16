class MoviesController < ApplicationController
  def index
    @active_tab = params[:tab].presence || "popular"
    service = TmdbService.new

    case @active_tab
    when "trending"
      response = service.trending(page: params[:page] || 1)
      @items = response["results"] || []
      @hero_item = @items.first
    when "tv"
      response = service.popular_tv(page: params[:page] || 1)
      @items = response["results"] || []
      @hero_item = @items.first
    else # popular movies
      response = service.popular_movies(page: params[:page] || 1)
      @items = response["results"] || []
      @hero_item = @items.first
    end

    # Preload user's watchlist item IDs for instant button states
    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end

    # Featured genre rows for homepage horizontal carousels
    if @active_tab == "popular"
      featured_genres = [
        { id: 878, name: "Bilimkurgu" },
        { id: 28, name: "Aksiyon" },
        { id: 18, name: "Dram" },
        { id: 35, name: "Komedi" }
      ]
      @genre_sections = featured_genres.map do |genre|
        res = service.discover_by_genre(genre[:id])
        {
          id: genre[:id],
          name: genre[:name],
          items: (res["results"] || []).first(10)
        }
      end
    else
      @genre_sections = []
    end
  end

  def show
    @movie = TmdbService.new.movie_details(params[:id])
    if @movie.blank? || @movie["id"].blank?
      redirect_to root_path, alert: "Film bulunamadı."
      return
    end

    @media_type = "movie"
    if user_signed_in?
      @watchlist_item = current_user.watchlists.find_by(tmdb_id: @movie["id"], media_type: "movie")
    end
    @community_posts = CommunityPost.where(tmdb_id: @movie["id"], media_type: "movie").recent.limit(5)
  end

  def search
    @query = params[:query].to_s.strip
    if @query.present?
      response = TmdbService.new.search_multi(query: @query, page: params[:page] || 1)
      @results = (response["results"] || []).select do |item|
        %w[movie tv].include?(item["media_type"]) || (item["title"].present? || item["name"].present?)
      end
    else
      @results = []
    end

    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end
  end

  def suggestions
    @query = params[:query].to_s.strip
    if @query.length >= 2
      response = TmdbService.new.search_multi(query: @query, page: 1)
      @results = (response["results"] || []).select do |item|
        %w[movie tv].include?(item["media_type"]) || (item["title"].present? || item["name"].present?)
      end.first(5)
    else
      @results = []
    end

    render layout: false
  end
end
