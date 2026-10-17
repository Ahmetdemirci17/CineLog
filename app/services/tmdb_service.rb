require "faraday"
require "json"

class TmdbService
  BASE_URL = "https://api.themoviedb.org/3"
  IMAGE_BASE_URL = "https://image.tmdb.org/t/p"

  def initialize(api_key: nil)
    @api_key = api_key || ENV["TMDB_API_KEY"] || Rails.application.credentials.dig(:tmdb, :api_key) || Rails.application.credentials.tmdb_api_key
  end

  # Popular Movies
  def popular_movies(page: 1, language: "tr-TR")
    fetch_with_cache("movie/popular", { page: page, language: language }) do
      fallback_popular_movies
    end
  end

  # Top Rated Movies (IMDb Top 250 style Bayesian weighted ranking)
  def top_rated_movies(page: 1, language: "tr-TR")
    page_num = [[page.to_i, 1].max, 500].min
    per_page = 20
    m_const = 12000.0
    c_const = 7.0
    cutoff_date = (Date.current - 120).to_s

    cache_key = "tmdb_bayesian_top_movies_v2/#{language}"
    ranked_pool = Rails.cache.fetch(cache_key, expires_in: 6.hours) do
      candidates = []

      (1..6).each do |p|
        res = fetch_with_cache("discover/movie", {
          without_genres: "99,10770",
          sort_by: "vote_count.desc",
          "vote_average.gte" => 7.5,
          "primary_release_date.lte" => cutoff_date,
          page: p,
          language: language
        })
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      (1..4).each do |p|
        res = fetch_with_cache("discover/movie", {
          without_genres: "99,10770",
          sort_by: "vote_average.desc",
          "vote_count.gte" => 5000,
          "primary_release_date.lte" => cutoff_date,
          page: p,
          language: language
        })
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      unique_movies = candidates.uniq { |m| m["id"] }
      unique_movies = fallback_popular_movies["results"] || [] if unique_movies.blank?
      unique_movies.sort_by { |m| -bayesian_score(m, m_const, c_const) }
    end

    offset = (page_num - 1) * per_page
    results = ranked_pool.slice(offset, per_page) || []

    {
      "page" => page_num,
      "results" => results,
      "total_pages" => [ranked_pool.size / per_page, 1].max,
      "total_results" => ranked_pool.size
    }
  end

  # Popular TV Shows
  def popular_tv(page: 1, language: "tr-TR")
    fetch_with_cache("tv/popular", { page: page, language: language }) do
      fallback_popular_tv
    end
  end

  # Trending TV Shows
  def trending_tv(time_window: "week", page: 1, language: "tr-TR")
    fetch_with_cache("trending/tv/#{time_window}", { page: page, language: language }) do
      fallback_popular_tv
    end
  end

  # Top Rated TV Shows (IMDb Top 250 TV style Bayesian weighted ranking)
  def top_rated_tv(page: 1, language: "tr-TR")
    page_num = [[page.to_i, 1].max, 500].min
    per_page = 20
    m_const = 4500.0
    c_const = 7.2
    cutoff_date = (Date.current - 90).to_s

    cache_key = "tmdb_bayesian_top_tv_v2/#{language}"
    ranked_pool = Rails.cache.fetch(cache_key, expires_in: 6.hours) do
      candidates = []

      (1..5).each do |p|
        res = fetch_with_cache("discover/tv", {
          without_genres: "10763,10764,10767",
          sort_by: "vote_count.desc",
          "vote_average.gte" => 7.5,
          "first_air_date.lte" => cutoff_date,
          page: p,
          language: language
        })
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      (1..4).each do |p|
        res = fetch_with_cache("discover/tv", {
          without_genres: "10763,10764,10767",
          sort_by: "vote_average.desc",
          "vote_count.gte" => 1500,
          "first_air_date.lte" => cutoff_date,
          page: p,
          language: language
        })
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      unique_shows = candidates.uniq { |t| t["id"] }
      unique_shows = fallback_popular_tv["results"] || [] if unique_shows.blank?
      unique_shows.each { |item| item["media_type"] ||= "tv" }
      unique_shows.sort_by { |t| -bayesian_score(t, m_const, c_const) }
    end

    offset = (page_num - 1) * per_page
    results = ranked_pool.slice(offset, per_page) || []

    {
      "page" => page_num,
      "results" => results,
      "total_pages" => [ranked_pool.size / per_page, 1].max,
      "total_results" => ranked_pool.size
    }
  end

  # Discover TV Shows by Genre ID (IMDb Bayesian weighted ranking & genre purity)
  def discover_tv_by_genre(genre_id, page: 1, sort_by: "vote_average.desc", language: "tr-TR")
    gid = genre_id.to_i
    m_const = 3500.0
    c_const = 7.2
    cutoff_date = (Date.current - 90).to_s
    without = tv_genre_exclusions(gid)

    cache_key = "tmdb_bayesian_tv_genre_v2/#{gid}/#{sort_by}/#{language}"
    ranked_pool = Rails.cache.fetch(cache_key, expires_in: 6.hours) do
      candidates = []

      (1..4).each do |p|
        params = {
          with_genres: gid,
          sort_by: "vote_count.desc",
          "vote_average.gte" => 7.2,
          "first_air_date.lte" => cutoff_date,
          page: p,
          language: language
        }
        params[:without_genres] = without if without.present?
        res = fetch_with_cache("discover/tv", params) { fallback_popular_tv }
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      (1..3).each do |p|
        params = {
          with_genres: gid,
          sort_by: "vote_average.desc",
          "vote_count.gte" => 1000,
          "first_air_date.lte" => cutoff_date,
          page: p,
          language: language
        }
        params[:without_genres] = without if without.present?
        res = fetch_with_cache("discover/tv", params) { fallback_popular_tv }
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      unique_shows = candidates.uniq { |t| t["id"] }
      filtered = unique_shows.select { |t| tv_genre_matches_purely?(t, gid) }
      filtered = unique_shows if filtered.size < 8
      filtered = fallback_popular_tv["results"] || [] if filtered.blank?
      filtered.each { |item| item["media_type"] ||= "tv" }
      filtered.sort_by { |t| -bayesian_score(t, m_const, c_const, gid) }
    end

    {
      "page" => page,
      "results" => ranked_pool.first(20),
      "total_pages" => 1,
      "total_results" => ranked_pool.size
    }
  end

  # Trending Content (movies + tv)
  def trending(time_window: "week", page: 1, language: "tr-TR")
    fetch_with_cache("trending/all/#{time_window}", { page: page, language: language }) do
      fallback_trending
    end
  end

  # Multi-search (movies, tv, people)
  def search_multi(query:, page: 1, language: "tr-TR")
    return { "results" => [], "total_results" => 0 } if query.blank?

    fetch_with_cache("search/multi", { query: query, page: page, language: language }) do
      fallback_search(query)
    end
  end

  # Movie Details
  def movie_details(id, language: "tr-TR")
    movie = fetch_with_cache("movie/#{id}", { language: language }) do
      fallback_movie_details(id)
    end

    return movie if movie.blank? || movie["id"].blank?

    # Fetch credits separately without triggering TMDB's tr-TR append_to_response encoding bug
    unless movie.key?("credits")
      credits = fetch_with_cache("movie/#{id}/credits", { language: language })
      movie["credits"] = credits if credits.is_a?(Hash) && credits["cast"].present?
    end

    # Fetch recommendations separately
    unless movie.key?("recommendations")
      recommendations = fetch_with_cache("movie/#{id}/recommendations", { language: language })
      movie["recommendations"] = recommendations if recommendations.is_a?(Hash) && recommendations["results"].present?
    end

    # Fetch videos separately (fallback to en-US if tr-TR has no videos)
    unless movie.key?("videos") && movie["videos"].is_a?(Hash) && movie["videos"]["results"].present?
      videos = fetch_with_cache("movie/#{id}/videos", { language: language })
      if videos.is_a?(Hash) && videos["results"].present?
        movie["videos"] = videos
      else
        en_videos = fetch_with_cache("movie/#{id}/videos", { language: "en-US" })
        movie["videos"] = en_videos if en_videos.is_a?(Hash) && en_videos["results"].present?
      end
    end

    movie
  end

  # TV Details
  def tv_details(id, language: "tr-TR")
    show = fetch_with_cache("tv/#{id}", { language: language }) do
      fallback_tv_details(id)
    end

    return show if show.blank? || show["id"].blank?

    unless show.key?("credits")
      credits = fetch_with_cache("tv/#{id}/credits", { language: language })
      show["credits"] = credits if credits.is_a?(Hash) && credits["cast"].present?
    end

    unless show.key?("recommendations")
      recommendations = fetch_with_cache("tv/#{id}/recommendations", { language: language })
      show["recommendations"] = recommendations if recommendations.is_a?(Hash) && recommendations["results"].present?
    end

    unless show.key?("videos") && show["videos"].is_a?(Hash) && show["videos"]["results"].present?
      videos = fetch_with_cache("tv/#{id}/videos", { language: language })
      if videos.is_a?(Hash) && videos["results"].present?
        show["videos"] = videos
      else
        en_videos = fetch_with_cache("tv/#{id}/videos", { language: "en-US" })
        show["videos"] = en_videos if en_videos.is_a?(Hash) && en_videos["results"].present?
      end
    end

    show
  end

  # Movie Genres List
  def genres(language: "tr-TR")
    fetch_with_cache("genre/movie/list", { language: language }) do
      fallback_genres
    end
  end

  # Discover Movies by Genre ID
  def discover_by_genre(genre_id, page: 1, sort_by: "popularity.desc", language: "tr-TR")
    if sort_by.to_s.include?("vote_average")
      return discover_top_rated_weighted(genre_id, page: page, language: language)
    end

    gid = genre_id.to_i
    without = movie_genre_exclusions(gid)
    min_votes = sort_by.to_s.include?("release_date") ? 50 : ([99, 10770].include?(gid) ? 100 : 300)

    params = {
      with_genres: gid,
      sort_by: sort_by,
      "vote_count.gte" => min_votes,
      page: page,
      language: language
    }
    params[:without_genres] = without if without.present?
    params["primary_release_date.lte"] = Date.current.to_s if sort_by.to_s.include?("release_date")

    res = fetch_with_cache("discover/movie", params) do
      fallback_discover_by_genre(gid)
    end

    if res.is_a?(Hash) && res["results"].is_a?(Array)
      filtered = res["results"].select { |m| movie_genre_matches_purely?(m, gid) }
      res = res.merge("results" => filtered) if filtered.size >= 6
    end

    res
  end

  # Person (Actor / Director) Details
  def person_details(id, language: "tr-TR")
    person = fetch_with_cache("person/#{id}", { language: language }) do
      fallback_person_details(id)
    end

    return person if person.blank? || person["id"].blank?

    # Fallback to English biography if Turkish biography is empty
    if person["biography"].blank?
      en_person = fetch_with_cache("person/#{id}", { language: "en-US" })
      if en_person.is_a?(Hash) && en_person["biography"].present?
        person["biography"] = en_person["biography"]
      end
    end

    person
  end

  # Person Combined Credits (Movies & TV Shows)
  def person_credits(id, language: "tr-TR")
    fetch_with_cache("person/#{id}/combined_credits", { language: language }) do
      fallback_person_credits(id)
    end
  end

  # Movie Recommendations (with similar fallback enrichment)
  def movie_recommendations(id, page: 1, language: "tr-TR")
    res = fetch_with_cache("movie/#{id}/recommendations", { page: page, language: language }) do
      { "results" => [] }
    end
    results = res.is_a?(Hash) ? (res["results"] || []).dup : []

    if results.size < 8
      similar = fetch_with_cache("movie/#{id}/similar", { page: page, language: language }) do
        { "results" => [] }
      end
      sim_results = similar.is_a?(Hash) ? (similar["results"] || []) : []
      results = (results + sim_results).uniq { |m| m["id"] }
      res["results"] = results if res.is_a?(Hash)
    end

    res.is_a?(Hash) ? res : { "results" => [] }
  end

  # TV Recommendations (with similar fallback enrichment)
  def tv_recommendations(id, page: 1, language: "tr-TR")
    res = fetch_with_cache("tv/#{id}/recommendations", { page: page, language: language }) do
      { "results" => [] }
    end
    results = res.is_a?(Hash) ? (res["results"] || []).dup : []

    if results.size < 8
      similar = fetch_with_cache("tv/#{id}/similar", { page: page, language: language }) do
        { "results" => [] }
      end
      sim_results = similar.is_a?(Hash) ? (similar["results"] || []) : []
      results = (results + sim_results).uniq { |m| m["id"] }
      res["results"] = results if res.is_a?(Hash)
    end

    res.is_a?(Hash) ? res : { "results" => [] }
  end

  # Image URL Helpers
  def self.poster_url(path, size: "w500")
    return nil if path.blank?
    return path if path.start_with?("http")
    "#{IMAGE_BASE_URL}/#{size}#{path}"
  end

  def self.backdrop_url(path, size: "original")
    return nil if path.blank?
    return path if path.start_with?("http")
    "#{IMAGE_BASE_URL}/#{size}#{path}"
  end

  # Extract YouTube trailer key from movie/tv item
  def self.trailer_key(media_item)
    return nil unless media_item.is_a?(Hash)
    videos = media_item.dig("videos", "results") || []
    return nil if videos.empty?

    # 1. Official YouTube Trailer
    trailer = videos.find { |v| v["site"] == "YouTube" && v["type"] == "Trailer" && v["key"].present? }
    # 2. Official YouTube Teaser
    trailer ||= videos.find { |v| v["site"] == "YouTube" && v["type"] == "Teaser" && v["key"].present? }
    # 3. Any YouTube video
    trailer ||= videos.find { |v| v["site"] == "YouTube" && v["key"].present? }
    trailer&.dig("key")
  end

  private

  # Conflicting genres to exclude per movie category so categories stay pure (e.g. no Pulp Fiction/Parasite in Comedy)
  def movie_genre_exclusions(genre_id)
    case genre_id.to_i
    when 35 # Komedi -> Exclude Drama, Thriller, War, Horror, History, Animation
      "18,53,10752,27,36,16"
    when 27 # Korku -> Exclude Animation, Family, War, History, Comedy, Romance
      "16,10751,10752,36,35,10749"
    when 80 # Suç -> Exclude Sci-Fi, Fantasy, Animation, Family, Adventure, Comedy
      "878,14,16,10751,12,35"
    when 10749 # Romantik -> Exclude Animation, Horror, Thriller, Crime, War, Sci-Fi
      "16,27,53,80,10752,878"
    when 99 # Belgesel -> Exclude Music concert films & TV specials
      "10402,10770"
    when 28, 12, 878, 14, 18, 53, 9648, 10752, 36, 37, 10402 # Live-action genres -> Exclude Animation (16) and Documentary (99)
      "16,99"
    else
      nil
    end
  end

  def tv_genre_exclusions(genre_id)
    case genre_id.to_i
    when 35 # Komedi -> Exclude Crime, War & Politics, Mystery, Talk/News/Reality
      "80,10768,9648,10763,10764,10767"
    when 80 # Suç -> Exclude Animation, Kids, Comedy, Talk/Reality
      "16,10762,35,10763,10764,10767"
    when 18, 9648 # Dram / Gizem -> Exclude Kids, Talk/Reality
      "10762,10763,10764,10767"
    else
      "10763,10764,10767"
    end
  end

  # Ensure the target genre is a primary/core genre of the movie, not a minor 3rd/4th sub-tag
  def movie_genre_matches_purely?(movie, genre_id)
    gid = genre_id.to_i
    gids = (movie["genre_ids"] || []).map(&:to_i)
    return true if gids.empty?
    return false unless gids.include?(gid)

    case gid
    when 35 # Komedi: must be 1st genre, or 2nd genre when not overshadowed by Action (28) / Crime (80) / Drama (18) / Thriller (53)
      return false if (gids & [18, 53, 27, 10752, 36, 16]).any?
      gids.first == 35 || (gids[0..1].include?(35) && !gids.include?(28) && !gids.include?(80))
    when 27 # Korku: must be 1st or 2nd genre, no Family/Animation/War
      return false if (gids & [16, 10751, 10752, 35]).any?
      gids[0..1].include?(27)
    when 80 # Suç: must be 1st or 2nd genre, no Sci-Fi/Fantasy/Animation
      return false if (gids & [878, 14, 16, 10751]).any?
      gids[0..1].include?(80)
    when 10749 # Romantik: must be 1st or 2nd genre
      return false if (gids & [16, 27, 53, 80, 10752]).any?
      gids[0..1].include?(10749)
    when 28, 12, 18, 14, 9648, 36, 10402
      return false if gids.include?(16)
      gids[0..1].include?(gid)
    when 878, 53, 10752, 37
      return false if gids.include?(16)
      gids[0..2].include?(gid)
    else
      true
    end
  end

  def tv_genre_matches_purely?(show, genre_id)
    gid = genre_id.to_i
    gids = (show["genre_ids"] || []).map(&:to_i)
    return true if gids.empty?
    return false unless gids.include?(gid)

    case gid
    when 35
      return false if (gids & [80, 10768, 9648]).any?
      gids[0..1].include?(35)
    when 80
      return false if (gids & [16, 10762, 35]).any?
      gids[0..1].include?(80)
    else
      gids[0..2].include?(gid)
    end
  end

  # IMDb Top 250 Bayesian formula:
  # WR = (v / (v + m)) * R + (m / (v + m)) * C
  # Includes high m_const confidence threshold so low-vote niche or brand-new titles cannot outrank true classics
  def bayesian_score(m, m_const = 10000.0, c_const = 7.0, target_genre_id = nil)
    v = m["vote_count"].to_f
    r = m["vote_average"].to_f
    base = ((v / (v + m_const)) * r) + ((m_const / (v + m_const)) * c_const)

    # Slight primary-genre relevance bonus when ranking inside a specific category
    if target_genre_id
      gids = (m["genre_ids"] || []).map(&:to_i)
      if gids.first == target_genre_id.to_i
        base += 0.08
      elsif gids[1] == target_genre_id.to_i
        base += 0.03
      end
    end

    base
  end

  # IMDb Top 250 style Bayesian Weighted Ranking for "En Beğenilenler"
  def discover_top_rated_weighted(genre_id, page: 1, language: "tr-TR")
    gid = genre_id.to_i
    page_num = [[page.to_i, 1].max, 500].min
    per_page = 20
    without = movie_genre_exclusions(gid)
    cutoff_date = (Date.current - 120).to_s

    # Genre-appropriate vote confidence threshold (m) and minimum vote floor
    m_const, min_votes, min_avg = case gid
    when 99, 10770 # Belgesel, TV Film
      [1500.0, 400, 7.2]
    when 37, 10402, 36, 10752 # Vahşi Batı, Müzik, Tarih, Savaş
      [5000.0, 1500, 7.2]
    when 27, 10749, 35 # Korku, Romantik, Komedi
      [8000.0, 2500, 7.0]
    else # Aksiyon, Dram, Bilimkurgu, Suç, Gerilim, Macera, Animasyon, Fantastik, Gizem
      [10000.0, 3000, 7.2]
    end
    c_const = 7.0

    # 1. Obtain baseline total count of movies in this genre
    base_params = { with_genres: gid, language: language }
    base_params[:without_genres] = without if without.present?
    base_res = fetch_with_cache("discover/movie", base_params)
    total_results = base_res.is_a?(Hash) && base_res["total_results"].present? ? base_res["total_results"].to_i : 10000
    total_pages = base_res.is_a?(Hash) && base_res["total_pages"].present? ? [[base_res["total_pages"].to_i, 1].max, 500].min : 500

    # 2. Build or fetch cached IMDb Bayesian top pool for the genre
    cache_key = "tmdb_bayesian_top_pool_v3/genre_#{gid}/#{language}"
    ranked_pool = Rails.cache.fetch(cache_key, expires_in: 6.hours) do
      candidates = []

      # Candidate set 1: top 160 most voted acclaimed movies in genre (pages 1..8)
      (1..8).each do |p|
        params = {
          with_genres: gid,
          sort_by: "vote_count.desc",
          "vote_average.gte" => min_avg,
          "vote_count.gte" => min_votes,
          "primary_release_date.lte" => cutoff_date,
          page: p,
          language: language
        }
        params[:without_genres] = without if without.present?
        res = fetch_with_cache("discover/movie", params)
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      # Candidate set 2: highest rated movies with strong vote floor (pages 1..4)
      (1..4).each do |p|
        params = {
          with_genres: gid,
          sort_by: "vote_average.desc",
          "vote_count.gte" => min_votes,
          "primary_release_date.lte" => cutoff_date,
          page: p,
          language: language
        }
        params[:without_genres] = without if without.present?
        res = fetch_with_cache("discover/movie", params)
        candidates.concat(res["results"] || []) if res.is_a?(Hash)
      end

      unique_movies = candidates.uniq { |m| m["id"] }
      pure_movies = unique_movies.select { |m| movie_genre_matches_purely?(m, gid) }
      pure_movies = unique_movies if pure_movies.size < 15

      if pure_movies.blank?
        fb = fallback_discover_by_genre(gid)
        pure_movies = fb["results"] || []
      end

      pure_movies.sort_by { |m| -bayesian_score(m, m_const, c_const, gid) }
    end

    max_full_pool_pages = [ranked_pool.size / per_page, 1].max

    results = if page_num <= max_full_pool_pages
      offset = (page_num - 1) * per_page
      ranked_pool.slice(offset, per_page) || []
    else
      direct_params = {
        with_genres: gid,
        sort_by: "vote_count.desc",
        "primary_release_date.lte" => cutoff_date,
        page: page_num,
        language: language
      }
      direct_params[:without_genres] = without if without.present?
      direct_res = fetch_with_cache("discover/movie", direct_params)
      list = direct_res.is_a?(Hash) && direct_res["results"].present? ? direct_res["results"] : []
      filtered_list = list.select { |m| movie_genre_matches_purely?(m, gid) }
      filtered_list = list if filtered_list.size < 6
      filtered_list.sort_by { |m| -bayesian_score(m, m_const, c_const, gid) }
    end

    {
      "page" => page_num,
      "results" => results,
      "total_pages" => total_pages,
      "total_results" => total_results
    }
  end

  def client
    @client ||= Faraday.new(url: BASE_URL) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
      f.options.timeout = 5
      f.options.open_timeout = 3
    end
  end

  def fetch_with_cache(endpoint, params = {})
    cache_key = "tmdb_api/#{endpoint}/#{Digest::MD5.hexdigest(params.to_s)}"

    Rails.cache.fetch(cache_key, expires_in: 2.hours) do
      if @api_key.blank?
        Rails.logger.warn "[TmdbService] TMDB_API_KEY is missing. Using fallback mock data."
        return yield if block_given?
        return { "results" => [] }
      end

      request_params = params.dup
      headers = { "Accept" => "application/json" }

      # Handle Bearer token (JWT) or query parameter (v3 API key)
      if @api_key.length > 50
        headers["Authorization"] = "Bearer #{@api_key}"
      else
        request_params[:api_key] = @api_key
      end

      response = client.get(endpoint, request_params, headers)

      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error "[TmdbService] API Error: HTTP #{response.status} for #{endpoint}"
        block_given? ? yield : { "results" => [], "error" => "HTTP #{response.status}" }
      end
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.error "[TmdbService] Exception #{e.class}: #{e.message}"
      block_given? ? yield : { "results" => [], "error" => e.message }
    end
  end

  # --- High-Quality Fallbacks when API key is not configured or network fails ---
  def fallback_popular_movies
    {
      "page" => 1,
      "results" => [
        {
          "id" => 157336,
          "title" => "Interstellar",
          "media_type" => "movie",
          "overview" => "İnsanlığın Dünya üzerindeki zamanı sona ererken, bir grup kaşif insanlık tarihinin en önemli görevini üstlenir.",
          "poster_path" => "/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
          "backdrop_path" => "/xJHokMbljvjADYdit5fK5VQsXEG.jpg",
          "vote_average" => 8.4,
          "release_date" => "2014-11-05"
        },
        {
          "id" => 872585,
          "title" => "Oppenheimer",
          "media_type" => "movie",
          "overview" => "J. Robert Oppenheimer'ın nükleer silahların geliştirilmesindeki rolü ve Manhattan Projesi hikayesi.",
          "poster_path" => "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg",
          "backdrop_path" => "/fm6KqXpk3M2HVveHwCrBSSBaO0V.jpg",
          "vote_average" => 8.1,
          "release_date" => "2023-07-19"
        },
        {
          "id" => 693134,
          "title" => "Dune: Part Two",
          "media_type" => "movie",
          "overview" => "Paul Atreides, ailesini yok eden komploculara karşı intikam arayışındayken Chani ve Fremen'lerle birleşir.",
          "poster_path" => "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
          "backdrop_path" => "/xOMo8BRK7PfcJv9JCnx7s5200bm.jpg",
          "vote_average" => 8.2,
          "release_date" => "2024-02-27"
        },
        {
          "id" => 27205,
          "title" => "Inception",
          "media_type" => "movie",
          "overview" => "Dom Cobb, insanların rüyalarından sırlarını çalan usta bir hırsızdır.",
          "poster_path" => "/edv5CZvWj09upOsy2Y6IwDhK8bt.jpg",
          "backdrop_path" => "/s3TBrRGB1iav7gFOCNx3H31MoES.jpg",
          "vote_average" => 8.4,
          "release_date" => "2010-07-15"
        }
      ]
    }
  end

  def fallback_popular_tv
    {
      "page" => 1,
      "results" => [
        {
          "id" => 94605,
          "name" => "Arcane",
          "media_type" => "tv",
          "overview" => "Piltover ve Zaun arasındaki çatışmada iki ikonik şampiyonun kökenleri ortaya çıkıyor.",
          "poster_path" => "/fqldf2t8ztc9aiwn3k6mlX3tvRT.jpg",
          "backdrop_path" => "/2rmK7mnchsl935x82Rp8ej7bqu5.jpg",
          "vote_average" => 8.8,
          "first_air_date" => "2021-11-06"
        },
        {
          "id" => 95557,
          "name" => "Severance",
          "media_type" => "tv",
          "overview" => "Mark Scout, çalışanlarının anılarının iş ve kişisel yaşamları arasında cerrahi olarak bölündüğü bir ekibe liderlik ediyor.",
          "poster_path" => "/3Pbt3qN6n40w2W1bKev14h6m92Z.jpg",
          "backdrop_path" => "/o6hT57Qy8e1tYw7bQ26oI5j8o3p.jpg",
          "vote_average" => 8.4,
          "first_air_date" => "2022-02-17"
        },
        {
          "id" => 1396,
          "name" => "Breaking Bad",
          "media_type" => "tv",
          "overview" => "Kanser teşhisi konan bir lise kimya öğretmeni, ailesinin geleceğini güvence altına almak için metamfetamin üretmeye başlar.",
          "poster_path" => "/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg",
          "backdrop_path" => "/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg",
          "vote_average" => 8.9,
          "first_air_date" => "2008-01-20"
        }
      ]
    }
  end

  def fallback_trending
    movies = fallback_popular_movies["results"]
    tv = fallback_popular_tv["results"]
    {
      "page" => 1,
      "results" => (movies + tv).shuffle
    }
  end

  def fallback_search(query)
    q = query.to_s.downcase
    all_items = fallback_popular_movies["results"] + fallback_popular_tv["results"]
    filtered = all_items.select do |item|
      (item["title"] || item["name"]).to_s.downcase.include?(q) ||
      item["overview"].to_s.downcase.include?(q)
    end
    { "page" => 1, "results" => filtered, "total_results" => filtered.size }
  end

  def fallback_movie_details(id)
    movie = fallback_popular_movies["results"].find { |m| m["id"].to_i == id.to_i }
    return nil unless movie

    movie.merge({
      "runtime" => 169,
      "genres" => [{ "id" => 878, "name" => "Bilimkurgu" }, { "id" => 18, "name" => "Dram" }],
      "credits" => {
        "cast" => [
          { "name" => "Matthew McConaughey", "character" => "Joseph Cooper", "profile_path" => "/e9ZHRY54GpqWVoes99EZ1yU47.jpg" },
          { "name" => "Anne Hathaway", "character" => "Dr. Amelia Brand", "profile_path" => "/tLMA93jYfvzgvCiHGaoDiLgJv9X.jpg" },
          { "name" => "Jessica Chastain", "character" => "Murphy Cooper", "profile_path" => "/jhDIfm96uYfe49hVv1F2U2f0e0h.jpg" }
        ]
      },
      "recommendations" => {
        "results" => fallback_popular_movies["results"].reject { |m| m["id"] == movie["id"] }
      }
    })
  end

  def fallback_tv_details(id)
    show = fallback_popular_tv["results"].find { |t| t["id"].to_i == id.to_i }
    return nil unless show

    show.merge({
      "number_of_seasons" => 2,
      "number_of_episodes" => 18,
      "genres" => [{ "id" => 18, "name" => "Dram" }, { "id" => 9648, "name" => "Gizem" }],
      "credits" => {
        "cast" => [
          { "name" => "Adam Scott", "character" => "Mark Scout", "profile_path" => "/khvM0UfP8G5m5YjFfL708dJ5k.jpg" },
          { "name" => "Patricia Arquette", "character" => "Harmony Cobel", "profile_path" => "/uV84q1uK9fJ4K5Vf6q1l.jpg" }
        ]
      },
      "recommendations" => {
        "results" => fallback_popular_tv["results"].reject { |t| t["id"] == show["id"] }
      }
    })
  end

  def fallback_genres
    {
      "genres" => [
        { "id" => 878, "name" => "Bilimkurgu" },
        { "id" => 28, "name" => "Aksiyon" },
        { "id" => 18, "name" => "Dram" },
        { "id" => 12, "name" => "Macera" },
        { "id" => 53, "name" => "Gerilim" },
        { "id" => 35, "name" => "Komedi" },
        { "id" => 27, "name" => "Korku" },
        { "id" => 16, "name" => "Animasyon" },
        { "id" => 9648, "name" => "Gizem" }
      ]
    }
  end

  def fallback_discover_by_genre(genre_id)
    all_items = fallback_popular_movies["results"]
    {
      "page" => 1,
      "results" => all_items.sort_by { |m| -m["vote_average"].to_f }
    }
  end

  def fallback_person_details(id)
    {
      "id" => id,
      "name" => "Oyuncu Bilgisi",
      "biography" => "Oyuncu biyografisi şu anda yüklenemedi.",
      "birthday" => nil,
      "place_of_birth" => nil,
      "profile_path" => nil,
      "known_for_department" => "Acting"
    }
  end

  def fallback_person_credits(id)
    {
      "cast" => fallback_popular_movies["results"]
    }
  end
end
