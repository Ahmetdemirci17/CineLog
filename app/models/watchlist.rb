class Watchlist < ApplicationRecord
  belongs_to :user

  enum :status, { plan_to_watch: 0, watched: 1 }

  validates :tmdb_id, presence: true
  validates :media_type, presence: true, inclusion: { in: %w[movie tv] }
  validates :title, presence: true
  validates :user_rating, numericality: { only_integer: true, in: 1..10 }, allow_nil: true
  validates :tmdb_id, uniqueness: { scope: [:user_id, :media_type], message: "has already been added to your watchlist" }

  scope :plan_to_watch, -> { where(status: :plan_to_watch).order(created_at: :desc) }
  scope :watched, -> { where(status: :watched).order(watched_at: :desc, updated_at: :desc) }

  before_save :fetch_metadata, if: -> { tmdb_id.present? && media_type.present? && (runtime.blank? || genres.blank?) }

  def fetch_metadata
    service = TmdbService.new
    details = Rails.cache.fetch("stats_details/#{media_type}/#{tmdb_id}", expires_in: 7.days) do
      media_type == "tv" ? service.tv_details(tmdb_id) : service.movie_details(tmdb_id)
    end
    if details.is_a?(Hash) && details["id"].present?
      self.runtime ||= media_type == "tv" ? (details["episode_run_time"]&.first || 45) : (details["runtime"] || 100)
      self.genres ||= (details["genres"] || []).map { |g| g["name"] }.join(", ")
    end
  rescue => e
    Rails.logger.warn("[Watchlist] Failed to fetch metadata for #{media_type}/#{tmdb_id}: #{e.message}")
  end

  def self.stats_for(user)
    watched_items = user.watchlists.watched
    total_watched = watched_items.count
    return nil if total_watched.zero?

    total_minutes = watched_items.sum(:runtime) || 0
    total_hours = total_minutes / 60
    days = total_hours / 24
    remaining_hours = total_hours % 24

    movies_count = watched_items.where(media_type: "movie").count
    tv_count = watched_items.where(media_type: "tv").count

    rated_items = watched_items.where.not(user_rating: nil)
    rated_count = rated_items.count
    avg_rating = rated_count.positive? ? rated_items.average(:user_rating).to_f.round(1) : nil

    genre_counts = Hash.new(0)
    watched_items.pluck(:genres).compact.each do |g_str|
      g_str.split(",").each do |g|
        genre = g.strip
        genre_counts[genre] += 1 if genre.present?
      end
    end

    total_genre_hits = genre_counts.values.sum
    top_genres = genre_counts.sort_by { |_, count| -count }.first(4).map do |genre, count|
      percentage = total_genre_hits.positive? ? ((count.to_f / total_genre_hits) * 100).round : 0
      { name: genre, count: count, percentage: percentage }
    end

    {
      total_watched: total_watched,
      movies_count: movies_count,
      tv_count: tv_count,
      total_minutes: total_minutes,
      total_hours: total_hours,
      days: days,
      remaining_hours: remaining_hours,
      rated_count: rated_count,
      avg_rating: avg_rating,
      top_genres: top_genres
    }
  end
end
