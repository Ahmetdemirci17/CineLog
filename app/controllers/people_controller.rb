class PeopleController < ApplicationController
  def show
    @person_id = params[:id]
    service = TmdbService.new
    @person = service.person_details(@person_id)

    if @person.blank? || @person["id"].blank?
      redirect_to root_path, alert: "Oyuncu bilgisi bulunamadı."
      return
    end

    credits_data = service.person_credits(@person_id)
    raw_cast = credits_data["cast"] || []

    # Calculate counts for tab filters
    @all_items = raw_cast.uniq { |c| [c["id"], c["media_type"]] }
    @movie_items = @all_items.select { |c| c["media_type"] == "movie" || (c["title"].present? && c["name"].blank?) }
    @tv_items = @all_items.select { |c| c["media_type"] == "tv" }

    @filter = params[:filter].presence || "all"
    @items = case @filter
             when "movie" then @movie_items
             when "tv"    then @tv_items
             else @all_items
             end

    # Sort primarily by vote_count + popularity so signature movies appear at the top
    @items = @items.sort_by { |item| -(item["vote_count"].to_i * 2 + item["popularity"].to_f) }

    if user_signed_in?
      @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    else
      @user_watchlist_map = {}
    end
  end
end
