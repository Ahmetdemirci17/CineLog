class TvShowsController < ApplicationController
  def index
    @active_tab = params[:tab].presence || "popular"
    service = TmdbService.new

    case @active_tab
    when "trending"
      response = service.trending_tv(page: params[:page] || 1)
    when "top_rated"
      response = service.top_rated_tv(page: params[:page] || 1)
    else
      @active_tab = "popular"
      response = service.popular_tv(page: params[:page] || 1)
    end

    @items = (response["results"] || []).each { |item| item["media_type"] ||= "tv" }
    @hero_item = @items.first

    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end

    # Personalized TV Recommendations
    if user_signed_in?
      @recommendation_source = current_user.watchlists.watched.where(media_type: "tv").reorder(user_rating: :desc, watched_at: :desc).first
      if @recommendation_source
        res = service.tv_recommendations(@recommendation_source.tmdb_id)
        all_user_ids = current_user.watchlists.where(media_type: "tv").pluck(:tmdb_id).to_set
        @recommended_items = (res["results"] || []).reject { |m| all_user_ids.include?(m["id"]) }.first(15)
        @recommended_items.each { |item| item["media_type"] ||= "tv" }
      else
        @recommended_items = []
      end
    else
      @recommended_items = []
    end

    # Featured TV genre rows for horizontal carousels
    featured_tv_genres = [
      { id: 10765, name: "Bilimkurgu & Fantazi" },
      { id: 18, name: "Dram" },
      { id: 80, name: "Suç" },
      { id: 9648, name: "Gizem" },
      { id: 35, name: "Komedi" }
    ]
    @genre_sections = featured_tv_genres.map do |genre|
      res = service.discover_tv_by_genre(genre[:id], sort_by: "vote_average.desc")
      {
        id: genre[:id],
        name: genre[:name],
        items: (res["results"] || []).first(15)
      }
    end
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
