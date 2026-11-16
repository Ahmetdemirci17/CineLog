class WatchlistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_watchlist, only: [:update, :destroy]

  def index
    @active_tab = params[:tab].presence || "plan_to_watch"
    @media_filter = %w[movie tv].include?(params[:media_type]) ? params[:media_type] : "all"

    base_plan = current_user.watchlists.plan_to_watch
    base_watched = current_user.watchlists.watched

    @plan_to_watch_total = base_plan.count
    @plan_to_watch_movies_count = base_plan.where(media_type: "movie").count
    @plan_to_watch_tv_count = base_plan.where(media_type: "tv").count

    @watched_total = base_watched.count
    @watched_movies_count = base_watched.where(media_type: "movie").count
    @watched_tv_count = base_watched.where(media_type: "tv").count

    @plan_to_watch_items = @media_filter == "all" ? base_plan : base_plan.where(media_type: @media_filter)
    @watched_items = @media_filter == "all" ? base_watched : base_watched.where(media_type: @media_filter)
    @user_watchlist_map = current_user.watchlists.index_by { |w| [w.tmdb_id, w.media_type] }
    @stats = Watchlist.stats_for(current_user)

    if @active_tab == "recommendations"
      service = TmdbService.new
      all_user_pairs = current_user.watchlists.pluck(:tmdb_id, :media_type).to_set

      if params[:source_id].present? && params[:source_id] != "all"
        source_id, source_type = parse_recommendation_source(params[:source_id], params[:source_type])
        source_scope = source_type ? base_watched.where(media_type: source_type) : base_watched
        @source_item = source_scope.find_by(tmdb_id: source_id)
        if @source_item
          @source_id = @source_item.tmdb_id
          @source_type = @source_item.media_type
          @source_title = @source_item.title
          res = @source_item.media_type == "tv" ? service.tv_recommendations(@source_item.tmdb_id) : service.movie_recommendations(@source_item.tmdb_id)
          items = (res["results"] || []).filter_map do |item|
            mtype = (item["media_type"].presence || @source_item.media_type).to_s
            next if all_user_pairs.include?([item["id"].to_i, mtype])
            item.merge("_recommended_by" => @source_item.title, "media_type" => mtype)
          end
          @recommendations = items.first(30)
        else
          @recommendations = []
        end
      else
        # Default or "all" -> Yüksek Puanlı İzlediklerimden Karma (Interleaved high-rating blend)
        @source_id = "all"
        @source_title = @media_filter == "tv" ? "Beğendiğim Dizilerden (Karma)" : (@media_filter == "movie" ? "Beğendiğim Filmlerden (Karma)" : "Beğendiğim Yapımlardan (Karma)")

        rec_data = Watchlist.mixed_recommendations_for(
          current_user,
          service: service,
          media_type: (@media_filter == "all" ? nil : @media_filter),
          limit: 36,
          max_sources: 10
        )
        @recommendations = rec_data[:items]
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
        format.html { refresh_or_redirect_back_or_to watchlists_path, notice: "#{@watchlist.title} listenize eklendi." }
      end
    else
      render_watchlist_error
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
        format.html { refresh_or_redirect_back_or_to watchlists_path, notice: "Durum güncellendi." }
      end
    else
      render_watchlist_error
    end
  end

  def destroy
    @tmdb_id = @watchlist.tmdb_id
    @media_type = @watchlist.media_type
    @watchlist.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { refresh_or_redirect_back_or_to watchlists_path, notice: "Listeden kaldırıldı." }
    end
  end

  private

  def set_watchlist
    @watchlist = current_user.watchlists.find(params[:id])
  end

  def parse_recommendation_source(raw_source, raw_type)
    str = raw_source.to_s
    if str.include?(":")
      parsed_type, parsed_id = str.split(":", 2)
      return [parsed_id, %w[movie tv].include?(parsed_type) ? parsed_type : nil]
    end
    [str, %w[movie tv].include?(raw_type) ? raw_type : nil]
  end

  def render_watchlist_error
    message = @watchlist.errors.full_messages.join(", ")
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.prepend("flash-messages", partial: "shared/error", locals: { message: message, toast: true }),
               status: :unprocessable_entity
      end
      format.html { redirect_back fallback_location: watchlists_path, alert: message }
    end
  end

  def watchlist_params
    params.require(:watchlist).permit(:tmdb_id, :media_type, :title, :poster_path, :status, :watched_at, :user_rating)
  end
end
