module Admin
  class DashboardController < BaseController
    def index
      @total_users = User.count
      @admin_users = User.admins.count
      @total_watchlists = Watchlist.count
      @watched_count = Watchlist.where(status: 1).count
      @plan_to_watch_count = Watchlist.where(status: 0).count
      @total_posts = CommunityPost.count
      @total_replies = CommunityReply.count

      @recent_users = User.order(created_at: :desc).limit(5)
      @recent_posts = CommunityPost.includes(:user).order(created_at: :desc).limit(5)
      @recent_watchlists = Watchlist.includes(:user).order(created_at: :desc).limit(5)
    end
  end
end
