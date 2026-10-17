module Admin
  class WatchlistsController < BaseController
    def index
      @watchlists = Watchlist.includes(:user).order(created_at: :desc)

      if params[:query].present?
        q = "%#{params[:query].strip.downcase}%"
        @watchlists = @watchlists.where("lower(title) LIKE ?", q)
      end

      if params[:media_type].present?
        @watchlists = @watchlists.where(media_type: params[:media_type])
      end

      if params[:status].present?
        @watchlists = @watchlists.where(status: params[:status])
      end

      @watchlists = @watchlists.page(params[:page]).per(25) if defined?(Kaminari)
    end

    def destroy
      @watchlist = Watchlist.find(params[:id])
      title = @watchlist.title
      user_name = @watchlist.user.username
      @watchlist.destroy
      redirect_back fallback_location: admin_watchlists_path, notice: "\"#{title}\" (#{user_name}) izleme kaydı silindi."
    end
  end
end
