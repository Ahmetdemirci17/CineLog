class WatchlistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_watchlist, only: [:update, :destroy]

  def index
    @active_tab = params[:tab].presence || "plan_to_watch"
    @plan_to_watch_items = current_user.watchlists.plan_to_watch
    @watched_items = current_user.watchlists.watched
    @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    @stats = Watchlist.stats_for(current_user)

    if @active_tab == "recommendations"
      service = TmdbService.new
      all_user_ids = current_user.watchlists.pluck(:tmdb_id).to_set

      if params[:source_id].present? && params[:source_id] != "all"
        @source_item = @watched_items.find_by(tmdb_id: params[:source_id])
        if @source_item
          @source_id = @source_item.tmdb_id
          @source_title = @source_item.title
          res = @source_item.media_type == "tv" ? service.tv_recommendations(@source_item.tmdb_id) : service.movie_recommendations(@source_item.tmdb_id)
          items = (res["results"] || []).reject { |m| all_user_ids.include?(m["id"]) }
          items.each { |item| item["_recommended_by"] = @source_item.title }
          @recommendations = items.first(30)
        else
          @recommendations = []
        end
      else
        # Default or "all" -> Tüm İzlediklerimden Karma (Interleaved diverse blend across watched library)
        @source_id = "all"
        @source_title = "Tüm İzlediklerim (Karma)"

        if @watched_items.any?
          all_watched_array = @watched_items.to_a
          # Truly random & diverse selection across all 60+ watched items on each refresh
          rated_items = all_watched_array.select { |w| w.user_rating.present? }.sort_by { |w| -w.user_rating.to_i }.first(4)
          remaining = all_watched_array - rated_items
          sample_count = [remaining.size, 12 - rated_items.size].min
          sources = (rated_items + remaining.sample(sample_count)).shuffle

          # Fetch recommendations for each source
          per_source_items = {}
          sources.each do |src|
            res = src.media_type == "tv" ? service.tv_recommendations(src.tmdb_id) : service.movie_recommendations(src.tmdb_id)
            items = (res["results"] || []).reject { |m| all_user_ids.include?(m["id"]) }
            items.each { |item| item["_recommended_by"] = src.title }
            per_source_items[src.id] = items
          end

          # Interleave (Round-robin) so recommendations are evenly balanced across all sources
          interleaved = []
          max_len = per_source_items.values.map(&:size).max || 0
          (0...max_len).each do |idx|
            sources.each do |src|
              item = per_source_items[src.id]&.[](idx)
              interleaved << item if item
            end
          end

          @recommendations = interleaved.uniq { |m| m["id"] }.first(36)
        else
          @recommendations = []
        end
      end
    else
      @recommendations = []
    end
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
