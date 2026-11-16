class MoviesController < ApplicationController
  def index
    @active_tab = params[:tab].presence || "popular"
    page = sanitized_page
    service = TmdbService.new

    case @active_tab
    when "trending"
      response = service.trending(page: page)
      @items = response["results"] || []
      @hero_item = @items.first
    when "top_rated"
      response = service.top_rated_movies(page: page)
      @items = response["results"] || []
      @hero_item = @items.first
    when "tv"
      response = service.popular_tv(page: page)
      @items = response["results"] || []
      @hero_item = @items.first
    else # popular movies
      response = service.popular_movies(page: page)
      @items = response["results"] || []
      @hero_item = @items.first
    end

    # Preload user's watchlist item IDs for instant button states
    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end

    # Personalized Mixed High-Rated Recommendations and genre shelves sit outside #movies_catalog
    catalog_frame_request = turbo_frame_request_id == "movies_catalog"
    @hero_item = nil if catalog_frame_request

    # Personalized Mixed High-Rated Recommendations for Homepage
    if !catalog_frame_request && user_signed_in? && @active_tab == "popular"
      top_grid_ids = @items.map { |m| m["id"].to_i }.to_set
      rec_data = Watchlist.mixed_recommendations_for(
        current_user,
        service: service,
        limit: 15,
        max_sources: 6,
        exclude_ids: top_grid_ids
      )
      @recommended_items = rec_data[:items]
      @recommendation_sources = rec_data[:sources]
      @based_on_high_ratings = rec_data[:based_on_high_ratings]
    else
      @recommended_items = []
      @recommendation_sources = []
      @based_on_high_ratings = false
    end

    # Featured genre rows for homepage horizontal carousels (zero cross-shelf duplicates)
    if !catalog_frame_request && @active_tab == "popular"
      featured_genres = [
        { id: 878, name: "Bilimkurgu" },
        { id: 28, name: "Aksiyon" },
        { id: 18, name: "Dram" },
        { id: 35, name: "Komedi" }
      ]
      already_shown_ids = (@items + @recommended_items).map { |m| m["id"].to_i }.to_set
      @genre_sections = service.build_unique_genre_sections(
        featured_genres,
        per_section: 15,
        exclude_ids: already_shown_ids
      )
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
    @watchlist_map = {}
    if user_signed_in?
      @watchlist_item = current_user.watchlists.find_by(tmdb_id: @movie["id"], media_type: "movie")
      rec_ids = Array(@movie.dig("recommendations", "results")).first(5).filter_map { |r| r["id"] }
      if rec_ids.any?
        @watchlist_map = current_user.watchlists.where(tmdb_id: rec_ids, media_type: "movie")
                                     .index_by { |w| [w.tmdb_id, w.media_type] }
      end
    end
    @community_posts = CommunityPost.where(tmdb_id: @movie["id"], media_type: "movie").recent.limit(5)
  end

  def search
    @query = params[:query].to_s.strip
    if @query.present?
      response = TmdbService.new.search_multi(query: @query, page: sanitized_page)
      all_results = response["results"] || []

      # Separate people and movies/series
      @people_results = all_results.select { |item| item["media_type"] == "person" }
      @media_results = all_results.select do |item|
        %w[movie tv].include?(item["media_type"]) || (item["media_type"] != "person" && (item["title"].present? || item["name"].present?))
      end
      @results = @media_results
    else
      @people_results = []
      @media_results = []
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
        %w[movie tv person].include?(item["media_type"]) || (item["title"].present? || item["name"].present?)
      end.first(6)
    else
      @results = []
    end

    render layout: false
  end
end
