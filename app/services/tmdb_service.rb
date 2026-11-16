require "faraday"
require "json"

class TmdbService
  BASE_URL = "https://api.themoviedb.org/3"
  IMAGE_BASE_URL = "https://image.tmdb.org/t/p"

  def initialize(api_key: nil)
    @api_key = api_key || ENV["TMDB_API_KEY"] || Rails.application.credentials.dig(:tmdb, :api_key) || Rails.application.credentials.tmdb_api_key
    client
  end

  # Popular Movies
  def popular_movies(page: 1, language: "tr-TR")
    fetch_with_cache("movie/popular", { page: page, language: language }) do
      fallback_popular_movies
    end
  end

  # Top Rated Movies (TMDB-calibrated Bayesian weighted ranking + franchise diversity)
  def top_rated_movies(page: 1, language: "tr-TR")
    page_num = [[page.to_i, 1].max, 500].min
    per_page = 20
    profile = { m_base: 2500.0, c_const: 7.35 }
    cutoff_date = (Date.current - 60).to_s

    cache_key = "tmdb_bayesian_top_movies_v4/#{language}"
    ranked_pool = cache_store.read(cache_key)

    if ranked_pool.blank?
      wave1 = [
        ["discover/movie", { without_genres: "99,10770", sort_by: "vote_count.desc", "vote_average.gte" => 7.4, "primary_release_date.lte" => cutoff_date, page: 1, language: language }],
        ["discover/movie", { without_genres: "99,10770", sort_by: "vote_average.desc", "vote_count.gte" => 1800, "primary_release_date.lte" => cutoff_date, page: 1, language: language }]
      ]
      first_responses = fetch_pages_parallel(wave1)
      candidates = first_responses.flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] }

      wave2 = []
      max_p1 = first_responses[0].is_a?(Hash) ? [first_responses[0]["total_pages"].to_i, 6].min : 0
      max_p2 = first_responses[1].is_a?(Hash) ? [first_responses[1]["total_pages"].to_i, 6].min : 0
      (2..max_p1).each do |p|
        wave2 << ["discover/movie", { without_genres: "99,10770", sort_by: "vote_count.desc", "vote_average.gte" => 7.4, "primary_release_date.lte" => cutoff_date, page: p, language: language }]
      end
      (2..max_p2).each do |p|
        wave2 << ["discover/movie", { without_genres: "99,10770", sort_by: "vote_average.desc", "vote_count.gte" => 1800, "primary_release_date.lte" => cutoff_date, page: p, language: language }]
      end
      candidates.concat(fetch_pages_parallel(wave2).flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] }) if wave2.any?

      unique_movies = candidates.uniq { |m| m["id"] }
      if unique_movies.present?
        sorted = unique_movies.sort_by { |m| [-genre_top_rated_score(m, nil, profile), -m["vote_count"].to_i, m["id"].to_i] }
        ranked_pool = apply_franchise_diversity(sorted, max_per_page: 2, per_page: per_page)
        cache_store.write(cache_key, ranked_pool, expires_in: 6.hours)
      else
        ranked_pool = fallback_popular_movies["results"] || []
      end
    end

    offset = (page_num - 1) * per_page
    results = ranked_pool.slice(offset, per_page) || []

    {
      "page" => page_num,
      "results" => results,
      "total_pages" => [(ranked_pool.size / per_page.to_f).ceil, 1].max,
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

  # Top Rated TV Shows (TMDB-calibrated Bayesian weighted ranking)
  def top_rated_tv(page: 1, language: "tr-TR")
    page_num = [[page.to_i, 1].max, 500].min
    per_page = 20
    profile = { m_base: 1200.0, c_const: 7.35 }
    cutoff_date = (Date.current - 60).to_s

    cache_key = "tmdb_bayesian_top_tv_v4/#{language}"
    ranked_pool = cache_store.read(cache_key)

    if ranked_pool.blank?
      wave1 = [
        ["discover/tv", { without_genres: "10763,10764,10767", sort_by: "vote_count.desc", "vote_average.gte" => 7.4, "first_air_date.lte" => cutoff_date, page: 1, language: language }],
        ["discover/tv", { without_genres: "10763,10764,10767", sort_by: "vote_average.desc", "vote_count.gte" => 600, "first_air_date.lte" => cutoff_date, page: 1, language: language }]
      ]
      first_responses = fetch_pages_parallel(wave1)
      candidates = first_responses.flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] }

      wave2 = []
      max_p1 = first_responses[0].is_a?(Hash) ? [first_responses[0]["total_pages"].to_i, 5].min : 0
      max_p2 = first_responses[1].is_a?(Hash) ? [first_responses[1]["total_pages"].to_i, 5].min : 0
      (2..max_p1).each do |p|
        wave2 << ["discover/tv", { without_genres: "10763,10764,10767", sort_by: "vote_count.desc", "vote_average.gte" => 7.4, "first_air_date.lte" => cutoff_date, page: p, language: language }]
      end
      (2..max_p2).each do |p|
        wave2 << ["discover/tv", { without_genres: "10763,10764,10767", sort_by: "vote_average.desc", "vote_count.gte" => 600, "first_air_date.lte" => cutoff_date, page: p, language: language }]
      end
      candidates.concat(fetch_pages_parallel(wave2).flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] }) if wave2.any?

      unique_shows = candidates.uniq { |t| t["id"] }
      if unique_shows.present?
        unique_shows.each { |item| item["media_type"] = "tv" }
        ranked_pool = unique_shows.sort_by { |t| [-genre_top_rated_score(t, nil, profile), -t["vote_count"].to_i, t["id"].to_i] }
        cache_store.write(cache_key, ranked_pool, expires_in: 6.hours)
      else
        ranked_pool = (fallback_popular_tv["results"] || []).map { |i| i.merge("media_type" => "tv") }
      end
    end

    offset = (page_num - 1) * per_page
    results = ranked_pool.slice(offset, per_page) || []

    {
      "page" => page_num,
      "results" => results,
      "total_pages" => [(ranked_pool.size / per_page.to_f).ceil, 1].max,
      "total_results" => ranked_pool.size
    }
  end

  # Discover TV Shows by Genre ID (TMDB-calibrated Bayesian weighted ranking & genre purity)
  def discover_tv_by_genre(genre_id, page: 1, sort_by: "vote_average.desc", per_page: 20, language: "tr-TR")
    gid = genre_id.to_i
    profile = { m_base: 900.0, c_const: 7.30 }
    cutoff_date = (Date.current - 60).to_s
    without = tv_genre_exclusions(gid)

    cache_key = "tmdb_bayesian_tv_genre_v4/#{gid}/#{sort_by}/#{language}"
    ranked_pool = cache_store.read(cache_key)

    if ranked_pool.blank?
      base_a = { with_genres: gid, sort_by: "vote_count.desc", "vote_average.gte" => 7.2, "first_air_date.lte" => cutoff_date, language: language }
      base_b = { with_genres: gid, sort_by: "vote_average.desc", "vote_count.gte" => 400, "first_air_date.lte" => cutoff_date, language: language }
      base_a[:without_genres] = without if without.present?
      base_b[:without_genres] = without if without.present?

      first_responses = fetch_pages_parallel([
        ["discover/tv", base_a.merge(page: 1)],
        ["discover/tv", base_b.merge(page: 1)]
      ])
      candidates = first_responses.flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] }

      wave2 = []
      max_p1 = first_responses[0].is_a?(Hash) ? [first_responses[0]["total_pages"].to_i, 4].min : 0
      max_p2 = first_responses[1].is_a?(Hash) ? [first_responses[1]["total_pages"].to_i, 4].min : 0
      (2..max_p1).each { |p| wave2 << ["discover/tv", base_a.merge(page: p)] }
      (2..max_p2).each { |p| wave2 << ["discover/tv", base_b.merge(page: p)] }
      candidates.concat(fetch_pages_parallel(wave2).flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] }) if wave2.any?

      unique_shows = candidates.uniq { |t| t["id"] }
      if unique_shows.present?
        filtered = unique_shows.select { |t| tv_genre_matches_purely?(t, gid) }
        filtered = unique_shows if filtered.empty?
        filtered.each { |item| item["media_type"] = "tv" }
        ranked_pool = filtered.sort_by { |t| [-tv_top_rated_score(t, gid, profile), -t["vote_count"].to_i, t["id"].to_i] }
        cache_store.write(cache_key, ranked_pool, expires_in: 6.hours)
      else
        ranked_pool = (fallback_popular_tv["results"] || []).map { |i| i.merge("media_type" => "tv") }
      end
    end

    page_num = [page.to_i, 1].max
    offset = (page_num - 1) * per_page

    {
      "page" => page_num,
      "results" => ranked_pool.slice(offset, per_page) || [],
      "total_pages" => [(ranked_pool.size / per_page.to_f).ceil, 1].max,
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
  def discover_by_genre(genre_id, page: 1, sort_by: "popularity.desc", per_page: 20, language: "tr-TR")
    if sort_by.to_s.include?("vote_average")
      return discover_top_rated_weighted(genre_id, page: page, per_page: per_page, language: language)
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
      valid = res["results"].reject { |m| movie_genre_hard_excluded?(m, gid) }
      pure = valid.select { |m| movie_genre_matches_purely?(m, gid) }
      chosen = pure.size >= 6 ? pure : valid
      res = res.merge("results" => chosen)
    end

    res
  end

  # Build cross-section deduplicated top-rated movie genre carousels where each multi-genre film
  # is assigned exclusively to the featured genre shelf with its strongest genre affinity.
  def build_unique_genre_sections(featured_genres, per_section: 15, exclude_ids: Set.new, language: "tr-TR")
    seen_ids = Set.new(exclude_ids.map(&:to_i))
    pools = {}
    rank_positions = {}

    featured_genres.each do |genre|
      gid = genre[:id].to_i
      res = discover_top_rated_weighted(gid, page: 1, per_page: 60, language: language)
      list = (res["results"] || []).reject { |m| seen_ids.include?(m["id"].to_i) }
      pools[gid] = list
      rank_positions[gid] = list.each_with_index.to_h { |m, idx| [m["id"].to_i, idx] }
    end

    featured_ids = featured_genres.map { |g| g[:id].to_i }
    best_genre_for_movie = {}

    pools.each do |gid, list|
      list.each do |movie|
        mid = movie["id"].to_i
        next if best_genre_for_movie.key?(mid)

        competing_gids = featured_ids.select { |fgid| rank_positions[fgid].key?(mid) }
        best_genre_for_movie[mid] = competing_gids.max_by do |fgid|
          [genre_affinity_adjustment(movie, fgid), -rank_positions[fgid][mid]]
        end
      end
    end

    featured_genres.map do |genre|
      gid = genre[:id].to_i
      assigned = (pools[gid] || []).select do |m|
        mid = m["id"].to_i
        best_genre_for_movie[mid] == gid && !seen_ids.include?(mid)
      end
      diversified = apply_franchise_diversity(assigned, max_per_page: 1, per_page: per_section).first(per_section)
      diversified.each { |m| seen_ids.add(m["id"].to_i) }

      {
        id: genre[:id],
        name: genre[:name],
        items: diversified
      }
    end
  end

  # Build cross-section deduplicated top-rated TV genre carousels
  def build_unique_tv_genre_sections(featured_genres, per_section: 15, exclude_ids: Set.new, language: "tr-TR")
    seen_ids = Set.new(exclude_ids.map(&:to_i))
    pools = {}
    rank_positions = {}

    featured_genres.each do |genre|
      gid = genre[:id].to_i
      res = discover_tv_by_genre(gid, page: 1, sort_by: "vote_average.desc", per_page: 50, language: language)
      list = (res["results"] || []).reject { |t| seen_ids.include?(t["id"].to_i) }
      pools[gid] = list
      rank_positions[gid] = list.each_with_index.to_h { |t, idx| [t["id"].to_i, idx] }
    end

    featured_ids = featured_genres.map { |g| g[:id].to_i }
    best_genre_for_show = {}

    pools.each do |_gid, list|
      list.each do |show|
        tid = show["id"].to_i
        next if best_genre_for_show.key?(tid)

        competing_gids = featured_ids.select { |fgid| rank_positions[fgid].key?(tid) }
        best_genre_for_show[tid] = competing_gids.max_by do |fgid|
          [tv_genre_affinity_adjustment(show, fgid), -rank_positions[fgid][tid]]
        end
      end
    end

    featured_genres.map do |genre|
      gid = genre[:id].to_i
      assigned = (pools[gid] || []).select do |t|
        tid = t["id"].to_i
        best_genre_for_show[tid] == gid && !seen_ids.include?(tid)
      end
      selected = assigned.first(per_section)
      selected.each { |t| seen_ids.add(t["id"].to_i) }

      {
        id: genre[:id],
        name: genre[:name],
        items: selected
      }
    end
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

  # Conflicting genres to exclude per movie category so categories stay pure
  # without accidentally banning acclaimed sub-genres (e.g. Comedy-Drama like Can Dostum / Grand Budapest Hotel)
  def movie_genre_exclusions(genre_id)
    case genre_id.to_i
    when 35 # Komedi -> Exclude Thriller, Horror, War, Animation, Documentary, TV Movie (keep Drama 18!)
      "53,27,10752,16,99,10770"
    when 27 # Korku -> Exclude Animation, Family, Romance, War, Documentary, TV Movie
      "16,10751,10749,10752,99,10770"
    when 80 # Suç -> Exclude Animation, Family, Horror, Sci-Fi, Documentary, TV Movie (keep Fantasy 14 & Comedy 35!)
      "16,10751,27,878,99,10770"
    when 10749 # Romantik -> Exclude Horror, Thriller, Crime, Action, Animation, Documentary, TV Movie (keep Sci-Fi 878!)
      "27,53,80,28,16,99,10770"
    when 99 # Belgesel -> Exclude Music concert films & TV specials
      "10402,10770"
    when 16 # Animasyon -> Exclude Documentary & TV specials
      "99,10770"
    when 10751 # Aile -> Exclude Horror, Thriller, Crime, War, Documentary
      "27,53,80,10752,99"
    when 10770 # TV Film
      "99"
    when 28, 12, 878, 14, 18, 53, 9648, 10752, 36, 37, 10402 # Live-action genres -> Exclude Animation, Documentary, TV Movie
      "16,99,10770"
    else
      nil
    end
  end

  def movie_genre_excluded_ids(genre_id)
    str = movie_genre_exclusions(genre_id)
    return [] if str.blank?
    str.split(",").map(&:to_i)
  end

  def movie_genre_hard_excluded?(movie, genre_id)
    gids = (movie["genre_ids"] || []).map(&:to_i)
    return false if gids.empty?
    (gids & movie_genre_excluded_ids(genre_id)).any?
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

  # Ensure the target genre is an authentic primary/core genre of the movie, not a minor 3rd/4th sub-tag
  def movie_genre_matches_purely?(movie, genre_id)
    gid = genre_id.to_i
    gids = (movie["genre_ids"] || []).map(&:to_i)
    return true if gids.empty?
    return false unless gids.include?(gid)
    return false if movie_genre_hard_excluded?(movie, gid)

    idx = gids.index(gid)
    return false if idx.nil? || idx >= 3

    case gid
    when 35 # Komedi: primary genre, or 2-genre comedy hybrid (e.g. [18, 35] Can Dostum); block 3-genre Sci-Fi/Action blockbusters
      return true if idx == 0
      idx == 1 && gids.size == 2 && (gids & [28, 878, 14]).empty?
    when 27 # Korku: must be 1st or 2nd genre; if paired with Comedy (35), Horror must be primary or 2-genre horror-comedy
      return false if gids.include?(35) && idx > 0 && gids.size > 2
      idx <= 1
    when 10749 # Romantik: 1st or 2nd genre, or classic 3-genre Drama/Sci-Fi/Comedy romance (e.g. Eternal Sunshine, Forrest Gump)
      idx <= 1 || (idx == 2 && (gids & [18, 35, 878]).size >= 2)
    when 28, 18 # Aksiyon, Dram: must be 1st or 2nd genre
      idx <= 1
    else
      idx <= 2
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

  # Genre-calibrated Bayesian parameters matched to TMDB's actual vote distribution
  def genre_ranking_profile(genre_id)
    case genre_id.to_i
    when 99, 10770 # Belgesel, TV Film
      { m_base: 400.0, tier1_votes: 220, tier2_votes: 90, continuation_votes: 40, min_avg: 7.1, c_const: 7.25, min_runtime: 45 }
    when 10752, 36, 37, 10402 # Savaş, Tarih, Vahşi Batı, Müzik
      { m_base: 900.0, tier1_votes: 500, tier2_votes: 220, continuation_votes: 100, min_avg: 7.1, c_const: 7.30, min_runtime: 65 }
    when 35, 10749 # Komedi, Romantik (higher m_base filters out fan-club / teen romcom vote anomalies)
      { m_base: 2300.0, tier1_votes: 900, tier2_votes: 400, continuation_votes: 180, min_avg: 7.0, c_const: 7.25, min_runtime: 65 }
    when 27, 9648, 10751 # Korku, Gizem, Aile
      { m_base: 1500.0, tier1_votes: 900, tier2_votes: 400, continuation_votes: 180, min_avg: 7.0, c_const: 7.25, min_runtime: 65 }
    when 16 # Animasyon
      { m_base: 2200.0, tier1_votes: 1400, tier2_votes: 600, continuation_votes: 250, min_avg: 7.2, c_const: 7.35, min_runtime: 60 }
    else # Aksiyon, Macera, Bilimkurgu, Dram, Gerilim, Suç, Fantastik
      { m_base: 2200.0, tier1_votes: 1400, tier2_votes: 600, continuation_votes: 250, min_avg: 7.2, c_const: 7.35, min_runtime: 65 }
    end
  end

  # Computes how strongly a movie belongs to target_genre_id so multi-genre blockbusters
  # don't dominate categories where they are merely a secondary/hybrid flavor.
  def genre_affinity_adjustment(movie, target_genre_id)
    return 0.0 if target_genre_id.nil?

    gid = target_genre_id.to_i
    gids = (movie["genre_ids"] || []).map(&:to_i)
    return 0.0 if gids.empty?

    idx = gids.index(gid)
    return -0.50 if idx.nil?

    adj = if gids.size == 1
      0.18
    elsif idx == 0 && gids.size == 2
      0.13
    elsif idx == 0
      0.08
    elsif idx == 1 && gids.size == 2
      0.06
    elsif idx == 1
      0.0
    elsif idx == 2 && ((gid == 878 && (gids - [878, 12, 18]).empty?) || (gid == 10752 && (gids - [10752, 18, 36]).empty?))
      0.03
    else
      -0.09
    end

    # Tonal cross-genre differentiation so each /katalog/:id page has its own authentic canon
    case gid
    when 28 # Aksiyon: demote space-opera / superhero sci-fi & high-fantasy quests so grounded Action classics shine
      adj -= 0.18 if (gids & [878, 14]).any?
    when 12 # Macera: demote urban/cyberpunk Sci-Fi-Action hybrids
      adj -= 0.20 if gids.include?(28) && gids.include?(878)
    when 35 # Komedi: demote crime capers, whodunits, and action-adventure hybrids below pure comedies & comedy-dramas
      adj -= 0.14 if (gids & [80, 28, 12, 878, 9648]).any?
      adj -= 0.14 if gids.include?(18) && idx > 0 && gids.size >= 3
    when 10749 # Romantik: demote comedy-drama side-plot romances while preserving sci-fi/drama love stories (e.g. Eternal Sunshine)
      adj -= 0.12 if idx >= 2 && gids.include?(35)
    when 53 # Gerilim: demote superhero/sci-fi action blockbusters below psychological & crime thrillers
      adj -= 0.16 if gids.first == 28 && (gids & [878, 12, 14]).any?
    when 18 # Dram: demote heavy action/sci-fi/fantasy spectacle blockbusters below true Dramas
      adj -= 0.15 if (gids & [28, 878, 12, 14]).size >= 2
    end

    adj
  end

  def tv_genre_affinity_adjustment(show, target_genre_id)
    return 0.0 if target_genre_id.nil?

    gid = target_genre_id.to_i
    gids = (show["genre_ids"] || []).map(&:to_i)
    return 0.0 if gids.empty?

    idx = gids.index(gid)
    return -0.50 if idx.nil?

    adj = gids.size == 1 ? 0.16 : (idx == 0 ? 0.10 : (idx == 1 ? 0.03 : -0.07))
    adj -= 0.14 if gid == 18 && (gids & [10765, 10759]).any?
    adj
  end

  # TMDB-calibrated Bayesian score with recency hype maturity damper + genre affinity
  def genre_top_rated_score(item, target_genre_id = nil, profile = nil)
    prof = profile || (target_genre_id ? genre_ranking_profile(target_genre_id) : { m_base: 2200.0, c_const: 7.35 })
    v = item["vote_count"].to_f
    r = item["vote_average"].to_f
    m_eff = effective_confidence_threshold(item, prof[:m_base].to_f)
    c_val = prof[:c_const].to_f

    base = ((v / (v + m_eff)) * r) + ((m_eff / (v + m_eff)) * c_val)
    base + genre_affinity_adjustment(item, target_genre_id)
  end

  def tv_top_rated_score(show, target_genre_id = nil, profile = { m_base: 900.0, c_const: 7.30 })
    v = show["vote_count"].to_f
    r = show["vote_average"].to_f
    m_eff = effective_confidence_threshold(show, profile[:m_base].to_f)
    c_val = profile[:c_const].to_f

    base = ((v / (v + m_eff)) * r) + ((m_eff / (v + m_eff)) * c_val)
    base + tv_genre_affinity_adjustment(show, target_genre_id)
  end

  def effective_confidence_threshold(item, m_base)
    raw_date = (item["release_date"].presence || item["first_air_date"]).to_s
    return m_base if raw_date.blank?

    release_date = Date.parse(raw_date)
    age_days = (Date.current - release_date).to_i
    if age_days < 365
      m_base * 2.2
    elsif age_days < 730
      m_base * 1.35
    else
      m_base
    end
  rescue ArgumentError
    m_base
  end

  # Extracts a normalized franchise root key from original_title / title so sequels share one key
  def franchise_key(movie)
    orig = movie["original_title"].to_s.strip
    loc = movie["title"].to_s.strip
    # Prefer a colon-prefixed title when available (e.g. "Yıldız Savaşları: ..." catches OT Star Wars sequels)
    source = if orig.include?(":")
      orig
    elsif loc.include?(":")
      loc
    else
      orig.presence || loc
    end
    return nil if source.blank?

    norm = source.downcase
    norm = norm.sub(/\A(the|a|an)\s+/i, "")

    if norm =~ /\A(harry potter|indiana jones|pirates of the caribbean|planet of the apes|fast & furious|mission: impossible|lord of the rings|star wars|james bond|john wick|toy story|back to the future|spider-man|avengers|godfather|dark knight|matrix|alien|terminator|rocky|rambo|mad max|jurassic park|jurassic world|hunger games|twilight|bourne|oceans|hangover|kung fu panda|shrek|how to train your dragon|ice age|despicable me|guardians of the galaxy|captain america|iron man|thor|deadpool|x-men|batman|superman)\b/i
      return Regexp.last_match(1).downcase
    end

    root = norm.split(/\s*[:–—]\s*|\s+-\s+/).first.to_s.strip
    root = root.sub(/\s+(part|vol\.?|volume|chapter|episode|bölüm)\s+([ivx]+|\d+|one|two|three|four|five)\z/i, "")
    root = root.sub(/\s+([2-9]|ii|iii|iv|v|vi|vii)\z/i, "")
    root = root.gsub(/[^[:alnum:]\s]/, " ").squeeze(" ").strip

    # Guard short words (e.g. "up", "it", "m") from colliding with unrelated titles
    root.length >= 4 ? root : "#{norm}_#{movie['id']}"
  end

  # Reorders ranked list into 20-item pages where any single franchise appears at most max_per_page times per page.
  # Deferred sequels are never deleted; they flow cleanly into subsequent pages.
  def apply_franchise_diversity(sorted_movies, max_per_page: 2, per_page: 20)
    return sorted_movies if sorted_movies.size <= max_per_page

    remaining = sorted_movies.dup
    output = []

    while remaining.any?
      page_bucket = []
      counts = Hash.new(0)
      deferred = []

      remaining.each do |movie|
        if page_bucket.size < per_page
          fkey = franchise_key(movie)
          if fkey.nil? || counts[fkey] < max_per_page
            page_bucket << movie
            counts[fkey] += 1 if fkey
          else
            deferred << movie
          end
        else
          deferred << movie
        end
      end

      # If only excess sequels of the same franchise remain at the very tail, flush them without infinite loop
      if page_bucket.empty?
        output.concat(deferred)
        break
      end

      output.concat(page_bucket)
      remaining = deferred
    end

    output
  end

  # TMDB-Calibrated Genre Top Rated Ranking Engine ("⭐ En Beğenilenler" on /katalog/:id)
  def discover_top_rated_weighted(genre_id, page: 1, per_page: 20, language: "tr-TR")
    gid = genre_id.to_i
    page_num = [[page.to_i, 1].max, 500].min
    without = movie_genre_exclusions(gid)
    cutoff_date = (Date.current - 60).to_s
    profile = genre_ranking_profile(gid)

    # 1. Build or read cached ranked pool (never caching transient errors or mock fallbacks)
    cache_key = "tmdb_bayesian_top_pool_v6/genre_#{gid}/#{language}"
    ranked_pool = cache_store.read(cache_key)

    if ranked_pool.blank?
      base_common = {
        with_genres: gid,
        "with_runtime.gte" => profile[:min_runtime],
        "primary_release_date.lte" => cutoff_date,
        language: language
      }
      base_common[:without_genres] = without if without.present?

      set_a_base = base_common.merge(sort_by: "vote_count.desc", "vote_average.gte" => profile[:min_avg], "vote_count.gte" => profile[:tier1_votes])
      set_b_base = base_common.merge(sort_by: "vote_average.desc", "vote_count.gte" => profile[:tier1_votes])
      set_c_base = base_common.merge(sort_by: "vote_average.desc", "vote_count.gte" => profile[:tier2_votes])

      # Wave 1: Fetch page 1 of all 3 complementary tiers in parallel
      first_wave = fetch_pages_parallel([
        ["discover/movie", set_a_base.merge(page: 1)],
        ["discover/movie", set_b_base.merge(page: 1)],
        ["discover/movie", set_c_base.merge(page: 1)]
      ])
      candidates = first_wave.flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] }

      # Wave 2: Only fetch remaining pages that actually exist in TMDB for this genre
      second_wave_reqs = []
      max_a = first_wave[0].is_a?(Hash) ? [first_wave[0]["total_pages"].to_i, 6].min : 0
      max_b = first_wave[1].is_a?(Hash) ? [first_wave[1]["total_pages"].to_i, 6].min : 0
      max_c = first_wave[2].is_a?(Hash) ? [first_wave[2]["total_pages"].to_i, 4].min : 0
      (2..max_a).each { |p| second_wave_reqs << ["discover/movie", set_a_base.merge(page: p)] }
      (2..max_b).each { |p| second_wave_reqs << ["discover/movie", set_b_base.merge(page: p)] }
      (2..max_c).each { |p| second_wave_reqs << ["discover/movie", set_c_base.merge(page: p)] }

      if second_wave_reqs.any?
        candidates.concat(fetch_pages_parallel(second_wave_reqs).flat_map { |r| r.is_a?(Hash) ? (r["results"] || []) : [] })
      end

      unique_movies = candidates.uniq { |m| m["id"] }
      if unique_movies.present?
        valid_movies = unique_movies.reject { |m| movie_genre_hard_excluded?(m, gid) }
        pure_movies = valid_movies.select { |m| movie_genre_matches_purely?(m, gid) }
        pure_movies = valid_movies if pure_movies.empty? || (pure_movies.size < 8 && valid_movies.size >= 15)

        sorted = pure_movies.sort_by do |m|
          [-genre_top_rated_score(m, gid, profile), -m["vote_count"].to_i, m["id"].to_i]
        end
        ranked_pool = apply_franchise_diversity(sorted, max_per_page: 2, per_page: 20)
        cache_store.write(cache_key, ranked_pool, expires_in: 6.hours) if ranked_pool.present?
      else
        fb = fallback_discover_by_genre(gid)
        ranked_pool = fb["results"] || []
      end
    end

    # 2. Obtain qualifying rated catalog count for accurate pagination metadata
    cont_base = {
      with_genres: gid,
      sort_by: "vote_average.desc",
      "with_runtime.gte" => profile[:min_runtime],
      "vote_count.gte" => profile[:continuation_votes],
      "vote_average.gte" => 6.6,
      "primary_release_date.lte" => cutoff_date,
      language: language
    }
    cont_base[:without_genres] = without if without.present?
    base_res = fetch_with_cache("discover/movie", cont_base.merge(page: 1))

    raw_total = base_res.is_a?(Hash) && base_res["total_results"].present? ? base_res["total_results"].to_i : 0
    total_results = [raw_total, ranked_pool.size].max
    total_pages = [[(total_results / per_page.to_f).ceil, 1].max, 500].min

    # 3. Disjoint zero-duplicate slice across ranked_pool + continuation stream
    offset = (page_num - 1) * per_page
    results = if offset < ranked_pool.size
      slice = (ranked_pool.slice(offset, per_page) || []).dup
      if slice.size < per_page && total_results > ranked_pool.size
        pool_ids = ranked_pool.each_with_object(Set.new) { |m, s| s.add(m["id"]) }
        extra = fetch_continuation_movies(
          gid: gid,
          cont_base: cont_base,
          skip_unseen: 0,
          needed: per_page - slice.size,
          exclude_ids: pool_ids,
          first_page_res: base_res
        )
        slice.concat(extra)
      end
      slice
    elsif total_results > ranked_pool.size
      pool_ids = ranked_pool.each_with_object(Set.new) { |m, s| s.add(m["id"]) }
      continuation_offset = [offset - ranked_pool.size, 0].max
      fetch_continuation_movies(
        gid: gid,
        cont_base: cont_base,
        skip_unseen: continuation_offset,
        needed: per_page,
        exclude_ids: pool_ids,
        first_page_res: base_res
      )
    else
      []
    end

    {
      "page" => page_num,
      "results" => results,
      "total_pages" => total_pages,
      "total_results" => total_results
    }
  end

  # Walks the deterministic continuation stream while skipping all IDs already present in ranked_pool,
  # ensuring strictly disjoint pages with zero duplicates across Page 1..N.
  def fetch_continuation_movies(gid:, cont_base:, skip_unseen:, needed:, exclude_ids:, first_page_res: nil)
    return [] if needed <= 0

    collected = []
    skipped = 0
    max_tmdb_pages = first_page_res.is_a?(Hash) ? [[first_page_res["total_pages"].to_i, 1].max, 60].min : 15
    # Start near an estimated TMDB page only when skip_unseen is very deep, else walk cleanly from page 1
    current_page = 1

    while current_page <= max_tmdb_pages && collected.size < needed
      res = current_page == 1 && first_page_res.is_a?(Hash) ? first_page_res : fetch_with_cache("discover/movie", cont_base.merge(page: current_page))
      break unless res.is_a?(Hash) && res["results"].is_a?(Array) && res["results"].any?

      res["results"].each do |movie|
        next if exclude_ids.include?(movie["id"])
        next if movie_genre_hard_excluded?(movie, gid)

        if skipped < skip_unseen
          skipped += 1
        else
          collected << movie
          break if collected.size >= needed
        end
      end

      current_page += 1
    end

    collected
  end

  def cache_store
    Rails.cache
  end

  def client
    Thread.current[:tmdb_faraday_client] ||= Faraday.new(url: BASE_URL) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
      f.options.timeout = 8
      f.options.open_timeout = 5
    end
  end

  def perform_http_get(endpoint, request_params, headers)
    attempts = 0
    begin
      attempts += 1
      res = client.get(endpoint, request_params, headers)
      if !res.success? && attempts < 2 && (res.status == 429 || res.status >= 500)
        sleep(0.35)
        res = client.get(endpoint, request_params, headers)
      end
      res
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed
      if attempts < 2
        Thread.current[:tmdb_faraday_client] = nil
        sleep(0.35)
        retry
      end
      raise
    end
  end

  # Fetches multiple [endpoint, params] requests using a bounded thread pool (max 3 threads)
  def fetch_pages_parallel(requests, max_threads: 3)
    return [] if requests.empty?
    return [fetch_with_cache(requests[0][0], requests[0][1])] if requests.size == 1

    results = Array.new(requests.size)
    queue = Queue.new
    requests.each_with_index { |req, idx| queue << [req, idx] }

    worker_count = [requests.size, max_threads].min
    workers = Array.new(worker_count) do
      Thread.new do
        loop do
          item = begin
            queue.pop(true)
          rescue ThreadError
            nil
          end
          break unless item

          (ep, prm), idx = item
          results[idx] = fetch_with_cache(ep, prm)
        end
      end
    end
    workers.each(&:join)
    results
  end

  # Poison-proof cache wrapper: ONLY writes successful valid TMDB JSON responses to cache_store.
  def fetch_with_cache(endpoint, params = {}, expires_in: 2.hours)
    normalized_params = params.sort_by { |k, _| k.to_s }.to_h
    cache_key = "tmdb_api/#{endpoint}/#{Digest::MD5.hexdigest(normalized_params.to_json)}"

    cached = cache_store.read(cache_key)
    return cached if cached.present?

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

    response = perform_http_get(endpoint, request_params, headers)

    if response.success?
      parsed = JSON.parse(response.body)
      cache_store.write(cache_key, parsed, expires_in: expires_in) if parsed.is_a?(Hash) && !parsed.key?("error")
      parsed
    else
      Rails.logger.error "[TmdbService] API Error: HTTP #{response.status} for #{endpoint}"
      block_given? ? yield : { "results" => [], "error" => "HTTP #{response.status}" }
    end
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.error "[TmdbService] Exception #{e.class}: #{e.message}"
    block_given? ? yield : { "results" => [], "error" => e.message }
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
          { "id" => 10297, "name" => "Matthew McConaughey", "character" => "Joseph Cooper", "profile_path" => "/e9ZHRY54GpqWVoes99EZ1yU47.jpg" },
          { "id" => 1813, "name" => "Anne Hathaway", "character" => "Dr. Amelia Brand", "profile_path" => "/tLMA93jYfvzgvCiHGaoDiLgJv9X.jpg" },
          { "id" => 83002, "name" => "Jessica Chastain", "character" => "Murphy Cooper", "profile_path" => "/jhDIfm96uYfe49hVv1F2U2f0e0h.jpg" }
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
          { "id" => 36801, "name" => "Adam Scott", "character" => "Mark Scout", "profile_path" => "/khvM0UfP8G5m5YjFfL708dJ5k.jpg" },
          { "id" => 10860, "name" => "Patricia Arquette", "character" => "Harmony Cobel", "profile_path" => "/uV84q1uK9fJ4K5Vf6q1l.jpg" }
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
