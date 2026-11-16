require "test_helper"

class TmdbServiceRankingTest < ActiveSupport::TestCase
  # Subclass with controllable fake API responses and isolated memory cache
  class FakeTmdbService < TmdbService
    attr_accessor :responder, :cache_backend

    def initialize(api_key: "test_api_key", cache_backend: ActiveSupport::Cache::MemoryStore.new, &responder)
      super(api_key: api_key)
      @cache_backend = cache_backend
      @responder = responder
    end

    private

    def cache_store
      @cache_backend
    end

    def perform_http_get(endpoint, request_params, _headers)
      raise "No responder configured" unless @responder
      @responder.call(endpoint, request_params)
    end
  end

  FakeResponse = Struct.new(:status, :body) do
    def success?
      status >= 200 && status < 300
    end
  end

  def json_ok(payload)
    FakeResponse.new(200, JSON.generate(payload))
  end

  def movie_hash(id:, title:, original_title: nil, vote_average:, vote_count:, genre_ids:, release_date: "2010-06-15")
    {
      "id" => id,
      "title" => title,
      "original_title" => original_title || title,
      "vote_average" => vote_average,
      "vote_count" => vote_count,
      "genre_ids" => genre_ids,
      "release_date" => release_date,
      "poster_path" => "/p#{id}.jpg"
    }
  end

  test "acclaimed genre classics outrank super-high-vote mediocre blockbusters and ultra-low-vote niche titles" do
    classic = movie_hash(
      id: 1, title: "Yaratık", original_title: "Alien",
      vote_average: 8.35, vote_count: 9_500, genre_ids: [878, 27], release_date: "1979-05-25"
    )
    pop_blockbuster = movie_hash(
      id: 2, title: "Galaksinin Koruyucuları", original_title: "Guardians of the Galaxy",
      vote_average: 7.90, vote_count: 36_000, genre_ids: [28, 878, 12], release_date: "2014-07-30"
    )
    low_vote_niche = movie_hash(
      id: 3, title: "Bilinmeyen Kısa Film", original_title: "Unknown Sci-Fi",
      vote_average: 8.50, vote_count: 350, genre_ids: [878], release_date: "2018-04-10"
    )

    service = FakeTmdbService.new do |_endpoint, params|
      page = params[:page].to_i
      results = page <= 1 ? [pop_blockbuster, classic, low_vote_niche] : []
      json_ok({ "page" => page, "results" => results, "total_pages" => 1, "total_results" => 3 })
    end

    res = service.discover_by_genre(878, page: 1, sort_by: "vote_average.desc")
    ids = res["results"].map { |m| m["id"] }

    assert_equal 1, ids.first, "8.35/9.5k classic must rank #1 ahead of 7.90/36k blockbuster"
    assert_operator ids.index(1), :<, ids.index(2)
    assert_operator ids.index(2), :<, ids.index(3)
  end

  test "recency maturity damper prevents brand-new hype movies from outranking proven classics of same rating" do
    recent_date = (Date.current - 90).to_s
    proven_classic = movie_hash(
      id: 10, title: "Kanıtlanmış Klasik", vote_average: 8.45, vote_count: 4_500,
      genre_ids: [18], release_date: "1995-09-20"
    )
    recent_hype = movie_hash(
      id: 11, title: "Yeni Vizyon Hype", vote_average: 8.48, vote_count: 4_500,
      genre_ids: [18], release_date: recent_date
    )

    service = FakeTmdbService.new do |_endpoint, params|
      page = params[:page].to_i
      json_ok({ "page" => page, "results" => (page <= 1 ? [recent_hype, proven_classic] : []), "total_pages" => 1, "total_results" => 2 })
    end

    res = service.discover_by_genre(18, page: 1, sort_by: "vote_average.desc")
    ids = res["results"].map { |m| m["id"] }
    assert_equal [10, 11], ids
  end

  test "comedy catalog restores acclaimed comedy-dramas while still blocking dark thrillers and demoting sci-fi adventures" do
    intouchables = movie_hash(
      id: 101, title: "Can Dostum", original_title: "Intouchables",
      vote_average: 8.28, vote_count: 17_000, genre_ids: [18, 35], release_date: "2011-11-02"
    )
    budapest = movie_hash(
      id: 102, title: "Büyük Budapeşte Oteli", original_title: "The Grand Budapest Hotel",
      vote_average: 8.05, vote_count: 14_500, genre_ids: [35, 18], release_date: "2014-02-26"
    )
    parasite = movie_hash(
      id: 103, title: "Parazit", original_title: "Parasite",
      vote_average: 8.50, vote_count: 18_500, genre_ids: [35, 53, 18], release_date: "2019-05-30"
    )
    teen_romcom = movie_hash(
      id: 104, title: "Gençlik Romantik Komedi", original_title: "Teen Romcom",
      vote_average: 7.55, vote_count: 9_000, genre_ids: [35, 10749], release_date: "2018-08-17"
    )

    captured_without_genres = []
    service = FakeTmdbService.new do |_endpoint, params|
      captured_without_genres << params[:without_genres].to_s
      page = params[:page].to_i
      results = page <= 1 ? [intouchables, budapest, parasite, teen_romcom] : []
      json_ok({ "page" => page, "results" => results, "total_pages" => 1, "total_results" => 4 })
    end

    res = service.discover_by_genre(35, page: 1, sort_by: "vote_average.desc")
    ids = res["results"].map { |m| m["id"] }

    # Drama (18) must NOT be excluded in TMDB query params for Comedy (35)
    captured_without_genres.compact_blank.each do |without_str|
      refute_includes without_str.split(","), "18", "Comedy must not hard-ban Drama (18)"
    end

    assert_includes ids, 101, "Can Dostum [18, 35] should be included in Comedy"
    assert_includes ids, 102, "Grand Budapest Hotel [35, 18] should be included in Comedy"
    refute_includes ids, 103, "Parasite [35, 53, 18] (Thriller) should remain excluded from Comedy"
    assert_operator ids.index(101), :<, ids.index(104)
    assert_operator ids.index(102), :<, ids.index(104)
  end

  test "franchise diversity limits same franchise to max 2 movies per 20-item catalog page without losing sequels" do
    avengers = [
      movie_hash(id: 201, title: "Avengers: Sonsuzluk Savaşı", original_title: "Avengers: Infinity War", vote_average: 8.35, vote_count: 32_000, genre_ids: [878, 28]),
      movie_hash(id: 202, title: "Avengers: Endgame", original_title: "Avengers: Endgame", vote_average: 8.33, vote_count: 30_000, genre_ids: [878, 28]),
      movie_hash(id: 203, title: "Yenilmezler", original_title: "The Avengers", vote_average: 8.30, vote_count: 35_000, genre_ids: [878, 28]),
      movie_hash(id: 204, title: "Yenilmezler: Ultron Çağı", original_title: "Avengers: Age of Ultron", vote_average: 8.28, vote_count: 25_000, genre_ids: [878, 28])
    ]
    standalones = (1..22).map do |i|
      movie_hash(
        id: 300 + i,
        title: "Bağımsız Bilimkurgu #{i}",
        original_title: "Standalone SciFi Alpha#{i}",
        vote_average: 8.15 - (i * 0.01),
        vote_count: 15_000,
        genre_ids: [878]
      )
    end
    all_movies = avengers + standalones

    service = FakeTmdbService.new do |_endpoint, params|
      page = params[:page].to_i
      slice = all_movies.slice((page - 1) * 20, 20) || []
      json_ok({ "page" => page, "results" => slice, "total_pages" => 2, "total_results" => all_movies.size })
    end

    p1 = service.discover_by_genre(878, page: 1, sort_by: "vote_average.desc")
    p2 = service.discover_by_genre(878, page: 2, sort_by: "vote_average.desc")

    p1_ids = p1["results"].map { |m| m["id"] }
    p2_ids = p2["results"].map { |m| m["id"] }
    avengers_ids = [201, 202, 203, 204]

    assert_equal 20, p1_ids.size
    assert_operator (p1_ids & avengers_ids).size, :<=, 2, "Page 1 must contain at most 2 Avengers movies"
    assert_equal 4, ((p1_ids + p2_ids) & avengers_ids).size, "Deferred franchise movies must appear on Page 2, not be lost"
    assert_empty (p1_ids & p2_ids), "No movie may repeat between Page 1 and Page 2"
  end

  test "catalog pagination has zero duplicates across pages and never drops partial pool remainder" do
    # 26 pool movies + 25 continuation movies
    pool_movies = (1..26).map do |i|
      movie_hash(
        id: 500 + i,
        title: "Klasik Film #{i}",
        original_title: "Classic Title #{i}_Unique",
        vote_average: 8.50 - (i * 0.02),
        vote_count: 6_000 - (i * 50),
        genre_ids: [18]
      )
    end
    continuation_movies = (27..55).map do |i|
      movie_hash(
        id: 500 + i,
        title: "Devam Film #{i}",
        original_title: "Continuation Title #{i}_Unique",
        vote_average: 7.40 - ((i - 26) * 0.01),
        vote_count: 900,
        genre_ids: [18]
      )
    end

    service = FakeTmdbService.new do |_endpoint, params|
      page = params[:page].to_i
      min_v = params["vote_count.gte"].to_i
      # Simulate pool queries vs lower-vote continuation stream (including overlap!)
      source = min_v >= 1000 ? pool_movies : (pool_movies + continuation_movies)
      slice = source.slice((page - 1) * 20, 20) || []
      json_ok({
        "page" => page,
        "results" => slice,
        "total_pages" => (source.size / 20.0).ceil,
        "total_results" => source.size
      })
    end

    p1 = service.discover_by_genre(18, page: 1, sort_by: "vote_average.desc")["results"].map { |m| m["id"] }
    p2 = service.discover_by_genre(18, page: 2, sort_by: "vote_average.desc")["results"].map { |m| m["id"] }
    p3 = service.discover_by_genre(18, page: 3, sort_by: "vote_average.desc")["results"].map { |m| m["id"] }

    assert_equal 20, p1.size
    assert p2.size >= 6, "Page 2 must NOT be empty; must include at least the 6 remainder movies from pool"
    # Remainder pool items 521..526 must appear on Page 2
    (521..526).each do |expected_id|
      assert_includes p2, expected_id, "Pool movie #{expected_id} must not be swallowed by integer division"
    end

    assert_empty (p1 & p2), "Page 1 and Page 2 must have zero duplicate movies"
    assert_empty (p1 & p3), "Page 1 and Page 3 must have zero duplicate movies"
    assert_empty (p2 & p3), "Page 2 and Page 3 must have zero duplicate movies"
  end

  test "transient network errors do not poison cache with fallback movies" do
    should_fail = true
    real_horror = [
      movie_hash(id: 901, title: "Cinnet", original_title: "The Shining", vote_average: 8.22, vote_count: 17_000, genre_ids: [27, 53]),
      movie_hash(id: 902, title: "Sapık", original_title: "Psycho", vote_average: 8.42, vote_count: 10_000, genre_ids: [27, 53, 9648])
    ]

    cache = ActiveSupport::Cache::MemoryStore.new
    service = FakeTmdbService.new(cache_backend: cache) do |_endpoint, params|
      raise Faraday::TimeoutError, "execution expired" if should_fail
      page = params[:page].to_i
      json_ok({ "page" => page, "results" => (page <= 1 ? real_horror : []), "total_pages" => 1, "total_results" => 2 })
    end

    # First call fails transiently
    first_res = service.discover_by_genre(27, page: 1, sort_by: "vote_average.desc")
    assert first_res.is_a?(Hash)

    # Second call succeeds and MUST NOT return cached Interstellar/Inception fallback!
    should_fail = false
    second_res = service.discover_by_genre(27, page: 1, sort_by: "vote_average.desc")
    titles = second_res["results"].map { |m| m["title"] }

    assert_includes titles, "Sapık"
    assert_includes titles, "Cinnet"
    refute_includes titles, "Interstellar"
  end

  test "build_unique_genre_sections assigns multi-genre movies to their highest-affinity shelf with zero duplicates" do
    dark_knight = movie_hash(id: 701, title: "Kara Şövalye", original_title: "The Dark Knight", vote_average: 8.52, vote_count: 35_000, genre_ids: [28, 80, 53])
    inception = movie_hash(id: 702, title: "Başlangıç", original_title: "Inception", vote_average: 8.37, vote_count: 38_000, genre_ids: [28, 878, 12])
    matrix = movie_hash(id: 703, title: "Matrix", original_title: "The Matrix", vote_average: 8.26, vote_count: 29_000, genre_ids: [28, 878])
    gladiator = movie_hash(id: 704, title: "Gladyatör", original_title: "Gladiator", vote_average: 8.23, vote_count: 21_000, genre_ids: [28, 18])
    shawshank = movie_hash(id: 705, title: "Esaretin Bedeli", original_title: "The Shawshank Redemption", vote_average: 8.73, vote_count: 31_000, genre_ids: [18, 80])

    all = [dark_knight, inception, matrix, gladiator, shawshank]

    service = FakeTmdbService.new do |_endpoint, params|
      gid = params[:with_genres].to_i
      page = params[:page].to_i
      matched = page <= 1 ? all.select { |m| m["genre_ids"].include?(gid) } : []
      json_ok({ "page" => page, "results" => matched, "total_pages" => 1, "total_results" => matched.size })
    end

    sections = service.build_unique_genre_sections([
      { id: 878, name: "Bilimkurgu" },
      { id: 28, name: "Aksiyon" },
      { id: 18, name: "Dram" }
    ], per_section: 15)

    all_shown_ids = sections.flat_map { |sec| sec[:items].map { |m| m["id"] } }
    assert_equal all_shown_ids.uniq.size, all_shown_ids.size, "No movie should appear in more than one genre section"

    scifi_ids = sections.find { |s| s[:id] == 878 }[:items].map { |m| m["id"] }
    action_ids = sections.find { |s| s[:id] == 28 }[:items].map { |m| m["id"] }
    drama_ids = sections.find { |s| s[:id] == 18 }[:items].map { |m| m["id"] }

    assert_includes scifi_ids, 702, "Inception should be placed in Sci-Fi"
    assert_includes scifi_ids, 703, "The Matrix should be placed in Sci-Fi"
    assert_includes action_ids, 701, "The Dark Knight should be placed in Action"
    assert_includes drama_ids, 705, "Shawshank should be placed in Drama"
  end
end
