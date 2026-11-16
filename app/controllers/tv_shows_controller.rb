class TvShowsController < ApplicationController
  def index
    @active_tab = params[:tab].presence || "popular"
    page = sanitized_page
    service = TmdbService.new

    case @active_tab
    when "trending"
      response = service.trending_tv(page: page)
    when "top_rated"
      response = service.top_rated_tv(page: page)
    else
      @active_tab = "popular"
      response = service.popular_tv(page: page)
    end

    @items = (response["results"] || []).each { |item| item["media_type"] ||= "tv" }
    @hero_item = @items.first

    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end

    # Personalized Mixed High-Rated TV Recommendations
    if user_signed_in?
      top_tv_ids = @items.map { |t| t["id"].to_i }.to_set
      rec_data = Watchlist.mixed_recommendations_for(
        current_user,
        service: service,
        media_type: "tv",
        limit: 15,
        max_sources: 6,
        exclude_ids: top_tv_ids
      )
      @recommended_items = rec_data[:items]
      @recommendation_sources = rec_data[:sources]
      @based_on_high_ratings = rec_data[:based_on_high_ratings]
    else
      @recommended_items = []
      @recommendation_sources = []
      @based_on_high_ratings = false
    end

    # Featured TV genre rows for horizontal carousels (zero cross-shelf duplicates)
    featured_tv_genres = [
      { id: 10765, name: "Bilimkurgu & Fantazi" },
      { id: 18, name: "Dram" },
      { id: 80, name: "Suç" },
      { id: 9648, name: "Gizem" },
      { id: 35, name: "Komedi" }
    ]
    already_shown_tv_ids = (@items + @recommended_items).map { |t| t["id"].to_i }.to_set
    @genre_sections = service.build_unique_tv_genre_sections(
      featured_tv_genres,
      per_section: 15,
      exclude_ids: already_shown_tv_ids
    )
  end

  def show
    @tv = TmdbService.new.tv_details(params[:id])
    if @tv.blank? || @tv["id"].blank?
      redirect_to root_path, alert: "Dizi bulunamadı."
      return
    end

    @media_type = "tv"
    if user_signed_in?
      @watchlist_item = current_user.watchlists.find_by(tmdb_id: @tv["id"], media_type: "tv")
    end
    @community_posts = CommunityPost.where(tmdb_id: @tv["id"], media_type: "tv").recent.limit(5)
  end
end
