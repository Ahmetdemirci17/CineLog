class TvShowsController < ApplicationController
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
