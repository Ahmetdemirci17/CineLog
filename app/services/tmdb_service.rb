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

  # Popular TV Shows
  def popular_tv(page: 1, language: "tr-TR")
    fetch_with_cache("tv/popular", { page: page, language: language }) do
      fallback_popular_tv
    end
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

    # Fetch videos separately
    unless movie.key?("videos")
      videos = fetch_with_cache("movie/#{id}/videos", { language: language })
      movie["videos"] = videos if videos.is_a?(Hash) && videos["results"].present?
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

    unless show.key?("videos")
      videos = fetch_with_cache("tv/#{id}/videos", { language: language })
      show["videos"] = videos if videos.is_a?(Hash) && videos["results"].present?
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
    params = {
      with_genres: genre_id,
      sort_by: sort_by,
      page: page,
      language: language
    }
    # When sorting strictly by vote_average, require at least 100 votes to avoid 1-vote 10/10 entries
    params["vote_count.gte"] = 100 if sort_by.to_s.include?("vote_average")

    fetch_with_cache("discover/movie", params) do
      fallback_discover_by_genre(genre_id)
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

  private

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
