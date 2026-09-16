class WatchlistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_watchlist, only: [:update, :destroy]

  def index
    @active_tab = params[:tab].presence || "plan_to_watch"
    @plan_to_watch_items = current_user.watchlists.plan_to_watch
    @watched_items = current_user.watchlists.watched
  end

  def create
    @watchlist = current_user.watchlists.find_or_initialize_by(
      tmdb_id: watchlist_params[:tmdb_id],
      media_type: watchlist_params[:media_type]
    )

    @watchlist.assign_attributes(watchlist_params)

    if @watchlist.status == "watched"
      @watchlist.watched_at ||= Time.current
    end

    if @watchlist.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: watchlists_path, notice: "#{@watchlist.title} listenize eklendi." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("watchlist_errors", partial: "shared/error", locals: { message: @watchlist.errors.full_messages.join(", ") }) }
        format.html { redirect_back fallback_location: watchlists_path, alert: @watchlist.errors.full_messages.join(", ") }
      end
    end
  end

  def update
    update_params = watchlist_params.to_h

    if update_params["status"] == "watched" && @watchlist.status != "watched"
      update_params["watched_at"] = Time.current if update_params["watched_at"].blank?
    end

    if @watchlist.update(update_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: watchlists_path, notice: "Durum güncellendi." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("watchlist_errors", partial: "shared/error", locals: { message: @watchlist.errors.full_messages.join(", ") }) }
        format.html { redirect_back fallback_location: watchlists_path, alert: @watchlist.errors.full_messages.join(", ") }
      end
    end
  end

  def destroy
    @tmdb_id = @watchlist.tmdb_id
    @media_type = @watchlist.media_type
    @watchlist.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: watchlists_path, notice: "Listeden kaldırıldı." }
    end
  end

  private

  def set_watchlist
    @watchlist = current_user.watchlists.find(params[:id])
  end

  def watchlist_params
    params.require(:watchlist).permit(:tmdb_id, :media_type, :title, :poster_path, :status, :watched_at, :user_rating)
  end
end
