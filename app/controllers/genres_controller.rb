class GenresController < ApplicationController
  def index
    service = TmdbService.new
    @genres = service.genres["genres"] || []

    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end
  end

  def show
    @genre_id = params[:id]
    @page = [params[:page].to_i, 1].max
    @sort_by = params[:sort_by].presence || "popularity.desc"

    service = TmdbService.new
    all_genres = service.genres["genres"] || []
    genre_obj = all_genres.find { |g| g["id"].to_s == @genre_id.to_s }
    @genre_name = genre_obj ? genre_obj["name"] : "Kategori ##{@genre_id}"

    response = service.discover_by_genre(@genre_id, page: @page, sort_by: @sort_by)
    @movies = response["results"] || []
    @total_pages = [response["total_pages"].to_i, 500].min
    @total_results = response["total_results"].to_i

    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end
  end
end
