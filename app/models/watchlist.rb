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
    cache_key = "stats_details/#{media_type}/#{tmdb_id}"
    details = Rails.cache.read(cache_key)
    unless details.is_a?(Hash) && details["id"].present?
      details = media_type == "tv" ? service.tv_details(tmdb_id) : service.movie_details(tmdb_id)
      Rails.cache.write(cache_key, details, expires_in: 7.days) if details.is_a?(Hash) && details["id"].present?
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

  # Builds an interleaved, diverse recommendation list driven by the user's highest-rated watched titles.
  # Never uses disliked/low-rated (<= 6) titles as recommendation sources.
  def self.mixed_recommendations_for(user, service: TmdbService.new, media_type: nil, limit: 15, max_sources: 6, exclude_ids: Set.new)
    return { items: [], sources: [], based_on_high_ratings: false } unless user

    scope = user.watchlists.watched
    scope = scope.where(media_type: media_type) if %w[movie tv].include?(media_type.to_s)
    watched_list = scope.to_a
    return { items: [], sources: [], based_on_high_ratings: false } if watched_list.empty?

    high_rated = watched_list.select { |w| w.user_rating.to_i >= 8 }
    good_rated = watched_list.select { |w| w.user_rating.to_i >= 7 }
    unrated = watched_list.select { |w| w.user_rating.nil? }

    candidate_pool, based_on_high = if high_rated.size >= 2
      [high_rated, true]
    elsif good_rated.any?
      [(good_rated + unrated.first(2)).uniq, true]
    elsif unrated.any?
      [unrated, false]
    else
      [watched_list.sort_by { |w| -w.user_rating.to_i }.first(3), false]
    end

    chosen_sources = weighted_sample_sources(candidate_pool, max_sources)
    blocked_pairs = user.watchlists.pluck(:tmdb_id, :media_type).to_set
    blocked_ids = Set.new(exclude_ids.map(&:to_i))

    per_source_items = {}
    chosen_sources.each do |src|
      res = src.media_type == "tv" ? service.tv_recommendations(src.tmdb_id) : service.movie_recommendations(src.tmdb_id)
      raw_items = res.is_a?(Hash) ? (res["results"] || []) : []

      cleaned = raw_items.filter_map do |item|
        next unless item.is_a?(Hash) && item["id"].present?
        iid = item["id"].to_i
        mtype = (item["media_type"].presence || src.media_type).to_s
        next if blocked_pairs.include?([iid, mtype]) || blocked_ids.include?(iid)
        if item.key?("vote_average") && item["vote_count"].to_i > 0
          next if item["vote_average"].to_f < 5.8
        end

        item.merge("_recommended_by" => src.title, "media_type" => mtype)
      end

      per_source_items[src.id] = cleaned
    end

    interleaved = []
    seen = Set.new
    max_len = per_source_items.values.map(&:size).max || 0
    (0...max_len).each do |idx|
      chosen_sources.each do |src|
        candidate = per_source_items[src.id]&.[](idx)
        next unless candidate
        key = [candidate["id"].to_i, candidate["media_type"]]
        next if seen.include?(key)

        seen.add(key)
        interleaved << candidate
        break if interleaved.size >= limit
      end
      break if interleaved.size >= limit
    end

    {
      items: interleaved.first(limit),
      sources: chosen_sources,
      based_on_high_ratings: based_on_high
    }
  end

  def self.weighted_sample_sources(pool, count)
    return pool.shuffle if pool.size <= count

    remaining = pool.dup
    picked = []
    count.times do
      break if remaining.empty?
      weights = remaining.map do |w|
        r = w.user_rating.to_i
        r >= 7 ? ((r - 5) ** 2) : 3
      end
      total_w = weights.sum.to_f
      target = rand * total_w
      running = 0.0
      chosen_idx = 0
      weights.each_with_index do |weight, idx|
        running += weight
        if target <= running
          chosen_idx = idx
          break
        end
      end
      picked << remaining.delete_at(chosen_idx)
    end
    picked
  end
  private_class_method :weighted_sample_sources
end
