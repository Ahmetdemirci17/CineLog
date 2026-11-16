require "test_helper"

class BugFixesTest < ActionDispatch::IntegrationTest
  setup do
    @suffix = SecureRandom.hex(4)
    @user = User.create!(
      email: "bugfix_#{@suffix}@example.com",
      username: "bugfix_#{@suffix}",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def with_env(key, val)
    prev = ENV[key]
    val.nil? ? ENV.delete(key) : ENV[key] = val
    yield
  ensure
    prev.nil? ? ENV.delete(key) : ENV[key] = prev
  end

  def with_stubbed_method(klass, method_name, replacement)
    had_method = klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
    original = klass.instance_method(method_name) if had_method
    klass.define_method(method_name, replacement)
    yield
  ensure
    if had_method
      klass.define_method(method_name, original)
    else
      klass.remove_method(method_name) if klass.method_defined?(method_name)
    end
  end

  # Bug 1: Offline fallback cast missing "id" and nil actor["id"] / actor["name"] crashes
  test "movies and tv_shows show pages render without crashing when offline fallback lacks cast ids or cast id is nil" do
    with_env("TMDB_API_KEY", "") do
      Rails.cache.clear
      get movie_path(157336)
      assert_response :success
      assert_includes response.body, "Matthew McConaughey"

      get tv_show_path(95557)
      assert_response :success
      assert_includes response.body, "Adam Scott"
    end

    nil_cast_movie = {
      "id" => 555001,
      "title" => "Castless Edge Movie",
      "overview" => "Overview",
      "vote_average" => 7.5,
      "release_date" => "2024-01-01",
      "genres" => [],
      "credits" => {
        "cast" => [
          { "id" => nil, "name" => "Ghost Actor", "character" => "Extra", "profile_path" => nil },
          { "id" => nil, "name" => "", "character" => "Anon", "profile_path" => nil }
        ]
      },
      "videos" => { "results" => [] },
      "recommendations" => { "results" => [] }
    }

    with_stubbed_method(TmdbService, :movie_details, ->(*_args, **_opts) { nil_cast_movie }) do
      get movie_path(555001)
      assert_response :success
      assert_includes response.body, "Ghost Actor"
    end

    nil_cast_tv = nil_cast_movie.merge("name" => "Castless Edge TV", "first_air_date" => "2024-01-01").except("title", "release_date")
    with_stubbed_method(TmdbService, :tv_details, ->(*_args, **_opts) { nil_cast_tv }) do
      get tv_show_path(555002)
      assert_response :success
      assert_includes response.body, "Ghost Actor"
    end
  end

  # Bug 1b: movies/show recommendations should reflect current_user's watchlist_map
  test "movies show recommendations show watchlist status for signed-in user" do
    @user.watchlists.create!(
      tmdb_id: 157336,
      media_type: "movie",
      title: "Interstellar",
      poster_path: "/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
      status: :watched,
      user_rating: 9,
      watched_at: Time.current
    )

    movie_with_rec = {
      "id" => 550,
      "title" => "Fight Club",
      "overview" => "Test overview",
      "vote_average" => 8.4,
      "release_date" => "1999-10-15",
      "genres" => [],
      "credits" => { "cast" => [] },
      "videos" => { "results" => [] },
      "recommendations" => {
        "results" => [
          {
            "id" => 157336,
            "title" => "Interstellar",
            "poster_path" => "/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
            "vote_average" => 8.4,
            "release_date" => "2014-11-05"
          }
        ]
      }
    }

    sign_in @user
    with_stubbed_method(TmdbService, :movie_details, ->(*_args, **_opts) { movie_with_rec }) do
      get movie_path(550)
      assert_response :success
      assert_includes response.body, "Puanı Değiştir / İncele"
    end
  end

  # Bug 2: PATCH /watchlists/:id on already-watched item must NOT remove card; transition plan_to_watch -> watched SHOULD remove card; error streams target flash-messages
  test "updating rating of watched item keeps its card while transitioning plan_to_watch to watched removes its card" do
    sign_in @user

    watched_item = @user.watchlists.create!(
      tmdb_id: 27205,
      media_type: "movie",
      title: "Inception",
      status: :watched,
      user_rating: 7,
      watched_at: Time.current
    )

    patch watchlist_path(watched_item), params: { watchlist: { user_rating: 10 } }, as: :turbo_stream
    assert_response :success
    assert_equal 10, watched_item.reload.user_rating
    refute_includes response.body, %(<turbo-stream action="remove" target="watchlist_card_#{watched_item.id}">)
    assert_includes response.body, %(target="watchlist_card_rating_#{watched_item.id}")
    assert_includes response.body, %(.watchlist-action-card-27205-movie)
    assert_includes response.body, %(.watchlist-action-hero-27205-movie)

    post watchlists_path, params: { watchlist: { tmdb_id: 998877, media_type: "movie", title: "Stream Created", status: "plan_to_watch" } }, as: :turbo_stream
    assert_response :success
    assert_includes response.body, %(.watchlist-action-card-998877-movie)
    assert_includes response.body, %(.watchlist-action-hero-998877-movie)
    created_item = @user.watchlists.find_by!(tmdb_id: 998877, media_type: "movie")

    delete watchlist_path(created_item), as: :turbo_stream
    assert_response :success
    assert_includes response.body, %(.watchlist-action-card-998877-movie)
    assert_includes response.body, %(.watchlist-action-hero-998877-movie)

    planned_item = @user.watchlists.create!(
      tmdb_id: 157336,
      media_type: "movie",
      title: "Interstellar",
      status: :plan_to_watch
    )

    patch watchlist_path(planned_item), params: { watchlist: { status: "watched", user_rating: 9 } }, as: :turbo_stream
    assert_response :success
    assert planned_item.reload.watched?
    assert_includes response.body, %(<turbo-stream action="remove" target="watchlist_card_#{planned_item.id}">)
  end

  test "watchlist validation errors via turbo_stream render into flash-messages rather than missing watchlist_errors" do
    sign_in @user

    post watchlists_path, params: { watchlist: { tmdb_id: 550, media_type: "invalid_type", title: "Bad" } }, as: :turbo_stream
    assert_response :unprocessable_entity
    refute_includes response.body, "watchlist_errors"
    assert_includes response.body, "flash-messages"

    item = @user.watchlists.create!(tmdb_id: 550, media_type: "movie", title: "Fight Club", status: :watched, user_rating: 8)
    patch watchlist_path(item), params: { watchlist: { user_rating: 99 } }, as: :turbo_stream
    assert_response :unprocessable_entity
    refute_includes response.body, "watchlist_errors"
    assert_includes response.body, "flash-messages"
  end

  # Bug 2b: Hero item appearing in both hero banner and cards grid must not produce duplicate watchlist_action DOM IDs
  test "movies and tv_shows index pages do not emit duplicate watchlist_action DOM ids for hero item" do
    fake_movie = {
      "id" => 777001,
      "title" => "Hero Duplicate Test",
      "overview" => "Overview",
      "poster_path" => "/poster.jpg",
      "backdrop_path" => "/backdrop.jpg",
      "vote_average" => 8.5,
      "release_date" => "2024-05-01"
    }
    fake_tv = fake_movie.merge("id" => 777002, "name" => "Hero TV Test", "first_air_date" => "2024-05-01").except("title", "release_date")

    with_stubbed_method(TmdbService, :top_rated_movies, ->(*_args, **_opts) { { "results" => [ fake_movie ], "total_pages" => 1 } }) do
      with_stubbed_method(TmdbService, :build_unique_genre_sections, ->(*_args, **_opts) { [] }) do
        get movies_path(tab: "top_rated")
        assert_response :success
        assert_operator response.body.scan(%(id="watchlist_action_777001_movie")).size, :<=, 1
      end
    end

    with_stubbed_method(TmdbService, :top_rated_tv, ->(*_args, **_opts) { { "results" => [ fake_tv ], "total_pages" => 1 } }) do
      with_stubbed_method(TmdbService, :build_unique_tv_genre_sections, ->(*_args, **_opts) { [] }) do
        get tv_shows_path(tab: "top_rated")
        assert_response :success
        assert_operator response.body.scan(%(id="watchlist_action_777002_tv")).size, :<=, 1
      end
    end
  end

  # Bug 3: Watchlists recommendations cross-media_type tmdb_id collision & source_type + media_type preservation
  test "watchlists recommendations separate movie and tv tmdb_id namespaces and respect source_type" do
    sign_in @user

    # User watched Movie 100 and TV 100, and also has TV 200 (NOT Movie 200) in watchlist
    @user.watchlists.create!(tmdb_id: 100, media_type: "movie", title: "Collision Movie", status: :watched, user_rating: 9, watched_at: Time.current)
    @user.watchlists.create!(tmdb_id: 100, media_type: "tv", title: "Collision TV", status: :watched, user_rating: 10, watched_at: Time.current)
    @user.watchlists.create!(tmdb_id: 200, media_type: "tv", title: "Only TV 200", status: :plan_to_watch)

    movie_recs = ->(_id) { { "results" => [ { "id" => 200, "title" => "Rec Movie 200", "vote_average" => 8.0, "release_date" => "2023-01-01" } ] } }
    tv_recs = ->(_id) { { "results" => [ { "id" => 300, "name" => "Rec TV 300", "vote_average" => 8.2, "first_air_date" => "2023-01-01" } ] } }

    with_stubbed_method(TmdbService, :movie_recommendations, movie_recs) do
      with_stubbed_method(TmdbService, :tv_recommendations, tv_recs) do
        # Movie 200 should NOT be excluded just because TV 200 is in watchlist
        get watchlists_path(tab: "recommendations", source_id: 100, source_type: "movie")
        assert_response :success
        assert_includes response.body, "Rec Movie 200"

        # Requesting source_type=tv with colliding tmdb_id=100 must resolve Collision TV, not Collision Movie
        get watchlists_path(tab: "recommendations", source_id: 100, source_type: "tv")
        assert_response :success
        assert_includes response.body, "Rec TV 300"
        refute_includes response.body, "Rec Movie 200"

        # Combined media_type:tmdb_id source parameter (used by dropdown) and media_type filter preservation
        get watchlists_path(tab: "recommendations", source_id: "tv:100", media_type: "tv")
        assert_response :success
        assert_includes response.body, "Rec TV 300"
        assert_includes response.body, "media_type=tv"
        assert_includes response.body, 'value="tv:100" selected'
      end
    end
  end

  # Bug 4: CommunityPost blank media_type normalization & failed TMDB attached media guard
  test "community post accepts blank media_type and ignores failed TMDB attached media responses" do
    sign_in @user

    assert_difference("CommunityPost.count", 1) do
      post community_posts_path, params: {
        community_post: {
          title: "Medyasız Genel Başlık",
          content: "Bu gönderide film veya dizi bağlanmadan genel tartışma açılıyor.",
          media_type: "",
          tmdb_id: ""
        }
      }
    end
    created = CommunityPost.order(:id).last
    assert_nil created.media_type
    assert_redirected_to community_post_path(created)

    post_with_bad_media = @user.community_posts.create!(
      title: "Hatalı Medya Testi",
      content: "TMDB hata döndürdüğünde bozuk kart gösterilmemeli.",
      tmdb_id: 999999999,
      media_type: "movie"
    )

    with_stubbed_method(TmdbService, :movie_details, ->(_id) { { "results" => [], "error" => "HTTP 404" } }) do
      get community_post_path(post_with_bad_media)
      assert_response :success
      refute_includes response.body, "Bahsedilen Yapım"
    end
  end

  # Bug 5: Watchlist#fetch_metadata cache poisoning & User.from_omniauth mixed-case email / nil auth
  test "watchlist fetch_metadata does not cache failed TMDB responses for 7 days" do
    mem_cache = ActiveSupport::Cache::MemoryStore.new
    orig_cache = Rails.cache
    Rails.cache = mem_cache

    key = "stats_details/movie/888999"
    attempt = 0
    flaky_movie_details = lambda do |_id|
      attempt += 1
      if attempt == 1
        { "results" => [], "error" => "HTTP 503" }
      else
        { "id" => 888999, "runtime" => 142, "genres" => [ { "name" => "Sci-Fi" } ] }
      end
    end

    with_stubbed_method(TmdbService, :movie_details, flaky_movie_details) do
      item = @user.watchlists.create!(tmdb_id: 888999, media_type: "movie", title: "Retryable Movie", status: :plan_to_watch)
      assert_equal 0, item.runtime.to_i
      assert_not mem_cache.exist?(key), "Failed TMDB response must not be cached"

      item.update!(status: :watched, user_rating: 8)
      assert_equal 142, item.runtime
      assert_includes item.genres, "Sci-Fi"
    end
  ensure
    Rails.cache = orig_cache
  end

  test "User.from_omniauth matches existing user email case-insensitively and handles nil auth" do
    assert_not User.from_omniauth(nil).persisted?

    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "uid-case-#{@suffix}",
      info: { email: @user.email.upcase, name: "Upper Case User" }
    )

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    post user_google_oauth2_omniauth_callback_path
    assert_redirected_to root_path
    assert_equal "uid-case-#{@suffix}", @user.reload.uid
  ensure
    OmniAuth.config.mock_auth.delete(:google_oauth2)
    OmniAuth.config.test_mode = false
  end

  # Bug 6: Pagination parameters <= 0 or non-numeric are clamped to >= 1
  test "movies, tv_shows, and genres controllers clamp non-positive page parameters to 1" do
    captured_pages = []

    with_stubbed_method(TmdbService, :top_rated_movies, ->(*_args, page: 1, **_opts) { captured_pages << [ :movies, page ]; { "results" => [], "total_pages" => 1 } }) do
      with_stubbed_method(TmdbService, :build_unique_genre_sections, ->(*_args, **_opts) { [] }) do
        get movies_path(tab: "top_rated", page: 0)
        assert_response :success
        get movies_path(tab: "top_rated", page: -3)
        assert_response :success
        get movies_path(tab: "top_rated", page: "abc")
        assert_response :success
      end
    end

    with_stubbed_method(TmdbService, :top_rated_tv, ->(*_args, page: 1, **_opts) { captured_pages << [ :tv, page ]; { "results" => [], "total_pages" => 1 } }) do
      with_stubbed_method(TmdbService, :build_unique_tv_genre_sections, ->(*_args, **_opts) { [] }) do
        get tv_shows_path(tab: "top_rated", page: -2)
        assert_response :success
      end
    end

    with_stubbed_method(TmdbService, :discover_by_genre, ->(_gid, page: 1, sort_by: "popularity.desc", **_opts) { captured_pages << [ :genre, page ]; { "results" => [], "total_pages" => 1 } }) do
      get genre_path(28, page: 0)
      assert_response :success
    end

    assert_equal [ [ :movies, 1 ], [ :movies, 1 ], [ :movies, 1 ], [ :tv, 1 ], [ :genre, 1 ] ], captured_pages
  end

  # Bug 7: Service worker must not cache /users auth pages or non-navigate HTML/Turbo fetches
  test "service worker excludes auth/user routes and avoids stale-while-revalidate for non-navigate HTML requests" do
    get "/service-worker.js"
    assert_response :success
    assert_includes response.body, "'/users'"
    assert_includes response.body, "destination"
    assert_equal File.read(Rails.root.join("app/views/pwa/service-worker.js")),
                 File.read(Rails.root.join("public/service-worker.js"))
  end
end
