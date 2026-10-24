class ProfilesController < ApplicationController
  def show
    @user = User.where("lower(username) = ?", params[:username].to_s.downcase).first
    if @user.nil?
      redirect_to root_path, alert: "Kullanıcı bulunamadı."
      return
    end

    @stats = Watchlist.stats_for(@user)
    @favorites = @user.watchlists.watched.where("user_rating >= ?", 9).reorder(user_rating: :desc, watched_at: :desc).limit(6)

    @current_tab = params[:tab].presence || "watched"

    case @current_tab
    when "plan_to_watch"
      @watchlists = @user.watchlists.plan_to_watch
    when "favorites"
      @watchlists = @user.watchlists.watched.where.not(user_rating: nil).reorder(user_rating: :desc, watched_at: :desc)
    when "community"
      @posts = @user.community_posts.includes(:community_replies).order(created_at: :desc)
    else # "watched"
      @watchlists = @user.watchlists.watched
    end

    # Apply media_type filter if provided
    if @watchlists && params[:media_type].present? && %w[movie tv].include?(params[:media_type])
      @watchlists = @watchlists.where(media_type: params[:media_type])
    end

    # Calculate taste match if current_user signed in and looking at another user
    if user_signed_in? && current_user != @user
      calculate_taste_match
    end
  end

  private

  def calculate_taste_match
    my_ratings = current_user.watchlists.where.not(user_rating: nil).index_by { |w| [w.tmdb_id, w.media_type] }
    their_ratings = @user.watchlists.where.not(user_rating: nil).index_by { |w| [w.tmdb_id, w.media_type] }

    common_keys = my_ratings.keys & their_ratings.keys
    if common_keys.any?
      total_score = common_keys.sum do |k|
        diff = (my_ratings[k].user_rating - their_ratings[k].user_rating).abs
        [100 - (diff * 15), 10].max
      end
      @taste_match_score = (total_score.to_f / common_keys.size).round
      @common_movies = common_keys.map do |k|
        {
          watchlist: their_ratings[k],
          my_rating: my_ratings[k].user_rating,
          their_rating: their_ratings[k].user_rating
        }
      end
    else
      @taste_match_score = nil
      @common_movies = []
    end
  end
end
