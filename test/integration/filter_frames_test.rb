require "test_helper"

class FilterFramesTest < ActionDispatch::IntegrationTest
  NATIVE_ANDROID_HEADERS = { "User-Agent" => "Hotwire Native Android" }.freeze

  setup do
    @suffix = SecureRandom.hex(4)
    @user = User.create!(
      email: "frames_#{@suffix}@example.com",
      username: "frames_#{@suffix}",
      password: "password123",
      password_confirmation: "password123"
    )

    @watched_movie = @user.watchlists.create!(
      tmdb_id: 6001,
      media_type: "movie",
      title: "Frame Test Movie",
      status: :watched,
      user_rating: 9,
      watched_at: Time.current,
      runtime: 120,
      genres: "Bilimkurgu"
    )
    @watched_tv = @user.watchlists.create!(
      tmdb_id: 6002,
      media_type: "tv",
      title: "Frame Test Series",
      status: :watched,
      user_rating: 8,
      watched_at: Time.current,
      runtime: 45,
      genres: "Dram"
    )
  end

  def with_stubbed_method(klass, method_name, replacement)
    had_method = klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
    original = klass.instance_method(method_name) if had_method
    klass.define_method(method_name, replacement)
    yield
  ensure
    if had_method
      klass.define_method(method_name, original)
    elsif klass.method_defined?(method_name)
      klass.remove_method(method_name)
    end
  end

  def with_stubbed_singleton_method(klass, method_name, replacement)
    sc = klass.singleton_class
    had_method = sc.method_defined?(method_name) || sc.private_method_defined?(method_name)
    original = sc.instance_method(method_name) if had_method
    sc.define_method(method_name, replacement)
    yield
  ensure
    if had_method
      sc.define_method(method_name, original)
    elsif sc.method_defined?(method_name)
      sc.remove_method(method_name)
    end
  end

  def sample_movie(id: 101, title: "Sample Movie")
    {
      "id" => id,
      "title" => title,
      "overview" => "Test overview",
      "poster_path" => "/poster.jpg",
      "backdrop_path" => "/backdrop.jpg",
      "vote_average" => 8.3,
      "release_date" => "2024-03-01",
      "media_type" => "movie"
    }
  end

  def sample_tv(id: 201, name: "Sample Show")
    {
      "id" => id,
      "name" => name,
      "overview" => "Test TV overview",
      "poster_path" => "/tv_poster.jpg",
      "backdrop_path" => "/tv_backdrop.jpg",
      "vote_average" => 8.6,
      "first_air_date" => "2024-04-01",
      "media_type" => "tv"
    }
  end

  test "movies index wraps filter tabs in movies_catalog frame and skips outer TMDB work on frame visits" do
    shelf_calls = 0
    rec_calls = 0
    popular = sample_movie
    trending = sample_movie(id: 102, title: "Trending Hit")

    with_stubbed_method(TmdbService, :popular_movies, ->(*_args, **_opts) { { "results" => [ popular ], "total_pages" => 1 } }) do
      with_stubbed_method(TmdbService, :trending, ->(*_args, **_opts) { { "results" => [ trending ], "total_pages" => 1 } }) do
        with_stubbed_method(TmdbService, :build_unique_genre_sections, ->(*_args, **_opts) { shelf_calls += 1; [] }) do
          with_stubbed_singleton_method(Watchlist, :mixed_recommendations_for, ->(*_args, **_opts) { rec_calls += 1; { items: [], sources: [], based_on_high_ratings: false } }) do
            sign_in @user

            # Web browser request includes turbo-action="advance" and computes outer sections
            get root_path
            assert_response :success
            assert_select "turbo-frame#movies_catalog.block[target='_top'][data-turbo-action='advance']", count: 1
            assert_select "turbo-frame#movies_catalog a[href='#{root_path(tab: 'trending')}'][data-turbo-frame='movies_catalog']", count: 1
            assert_select "turbo-frame#movies_catalog a[href='#{movie_path(101)}']:not([data-turbo-frame])", minimum: 1
            assert_equal 1, shelf_calls
            assert_equal 1, rec_calls

            # Hotwire Native omits turbo-action="advance" so frame switches do not push a native fragment
            get root_path(tab: "trending"), headers: NATIVE_ANDROID_HEADERS
            assert_response :success
            assert_select "turbo-frame#movies_catalog.block[target='_top']", count: 1
            assert_select "turbo-frame#movies_catalog[data-turbo-action]", count: 0

            # Turbo-Frame targeted visit to popular tab skips hero, recommendations, and genre carousels
            get root_path(tab: "popular"), headers: NATIVE_ANDROID_HEADERS.merge("Turbo-Frame" => "movies_catalog")
            assert_response :success
            assert_select "turbo-frame#movies_catalog", count: 1
            assert_equal 1, shelf_calls
            assert_equal 1, rec_calls
          end
        end
      end
    end
  end

  test "tv_shows index wraps filter tabs in tv_shows_catalog frame and skips outer sections on frame visits" do
    tv_shelf_calls = 0
    popular = sample_tv
    trending = sample_tv(id: 202, name: "Trending Show")

    with_stubbed_method(TmdbService, :popular_tv, ->(*_args, **_opts) { { "results" => [ popular ], "total_pages" => 1 } }) do
      with_stubbed_method(TmdbService, :trending_tv, ->(*_args, **_opts) { { "results" => [ trending ], "total_pages" => 1 } }) do
        with_stubbed_method(TmdbService, :build_unique_tv_genre_sections, ->(*_args, **_opts) { tv_shelf_calls += 1; [] }) do
          get tv_shows_path
          assert_response :success
          assert_select "turbo-frame#tv_shows_catalog.block[target='_top'][data-turbo-action='advance']", count: 1
          assert_select "turbo-frame#tv_shows_catalog a[href='#{tv_shows_path(tab: 'trending')}'][data-turbo-frame='tv_shows_catalog']", count: 1
          assert_equal 1, tv_shelf_calls

          get tv_shows_path(tab: "trending"), headers: NATIVE_ANDROID_HEADERS.merge("Turbo-Frame" => "tv_shows_catalog")
          assert_response :success
          assert_select "turbo-frame#tv_shows_catalog.block[target='_top']", count: 1
          assert_select "turbo-frame#tv_shows_catalog[data-turbo-action]", count: 0
          assert_equal 1, tv_shelf_calls
        end
      end
    end
  end

  test "genres show wraps sorting and pagination in genre_catalog frame while back link breaks out" do
    movie = sample_movie

    with_stubbed_method(TmdbService, :genres, -> { { "genres" => [ { "id" => 28, "name" => "Aksiyon" } ] } }) do
      with_stubbed_method(TmdbService, :discover_by_genre, ->(*_args, **_opts) { { "results" => [ movie ], "total_pages" => 3, "total_results" => 60 } }) do
        get genre_path(28)
        assert_response :success
        assert_select "turbo-frame#genre_catalog.block[target='_top'][data-turbo-action='advance']", count: 1
        assert_select "turbo-frame#genre_catalog a[href='#{genres_path}']:not([data-turbo-frame])", count: 1
        assert_select "turbo-frame#genre_catalog a[href='#{genre_path(28, sort_by: 'vote_average.desc', page: 1)}'][data-turbo-frame='genre_catalog']", count: 1
        assert_select "turbo-frame#genre_catalog a[href='#{genre_path(28, page: 2, sort_by: 'popularity.desc')}'][data-turbo-frame='genre_catalog']", minimum: 1
        assert_select "turbo-frame#genre_catalog form[action='#{genre_path(28)}'][data-turbo-frame='genre_catalog']", count: 1

        get genre_path(28, sort_by: "vote_average.desc", page: 1), headers: NATIVE_ANDROID_HEADERS
        assert_response :success
        assert_select "turbo-frame#genre_catalog[data-turbo-action]", count: 0
      end
    end
  end

  test "people show wraps filmography filters in person_filmography frame" do
    movie = sample_movie
    tv = sample_tv

    with_stubbed_method(TmdbService, :person_details, ->(_id) { { "id" => 10297, "name" => "Matthew McConaughey" } }) do
      with_stubbed_method(TmdbService, :person_credits, ->(_id) { { "cast" => [ movie, tv ] } }) do
        get person_path(10297)
        assert_response :success
        assert_select "turbo-frame#person_filmography.block[target='_top'][data-turbo-action='advance']", count: 1
        assert_select "turbo-frame#person_filmography a[href='#{person_path(10297, filter: 'all')}'][data-turbo-frame='person_filmography']", count: 1
        assert_select "turbo-frame#person_filmography a[href='#{person_path(10297, filter: 'movie')}'][data-turbo-frame='person_filmography']", count: 1
        assert_select "turbo-frame#person_filmography a[href='#{person_path(10297, filter: 'tv')}'][data-turbo-frame='person_filmography']", count: 1

        get person_path(10297, filter: "movie"), headers: NATIVE_ANDROID_HEADERS
        assert_response :success
        assert_select "turbo-frame#person_filmography[data-turbo-action]", count: 0
      end
    end
  end

  test "profiles show wraps tabs and media filters in profile_content frame" do
    get user_profile_path(@user.username)
    assert_response :success
    assert_select "turbo-frame#profile_content.block.space-y-8[target='_top'][data-turbo-action='advance']", count: 1
    assert_select "turbo-frame#profile_content a[href='#{user_profile_path(@user.username, tab: 'plan_to_watch')}'][data-turbo-frame='profile_content']", count: 1
    assert_select "turbo-frame#profile_content a[href='#{user_profile_path(@user.username, tab: 'watched', media_type: 'movie')}'][data-turbo-frame='profile_content']", count: 1
    assert_select "turbo-frame#profile_content a[href='#{movie_path(@watched_movie.tmdb_id)}']:not([data-turbo-frame])", minimum: 1

    get user_profile_path(@user.username, tab: "watched", media_type: "tv"), headers: NATIVE_ANDROID_HEADERS
    assert_response :success
    assert_select "turbo-frame#profile_content[data-turbo-action]", count: 0
  end

  test "watchlists index wraps tabs, media filters, and recommendation controls in watchlists_content frame" do
    sign_in @user

    get watchlists_path(tab: "watched")
    assert_response :success
    assert_select "turbo-frame#watchlists_content.block[target='_top'][data-turbo-action='advance']", count: 1
    assert_select "turbo-frame#watchlists_content a[href='#{watchlists_path(tab: 'plan_to_watch')}'][data-turbo-frame='watchlists_content']", count: 1
    assert_select "turbo-frame#watchlists_content a[href='#{watchlists_path(tab: 'watched', media_type: 'movie')}'][data-turbo-frame='watchlists_content']", count: 1
    assert_select "turbo-frame#watchlists_content a[href='#{watchlists_path(tab: 'recommendations', source_id: @watched_movie.tmdb_id, source_type: 'movie')}'][data-turbo-frame='watchlists_content']", count: 1

    rec_movie = sample_movie(id: 701, title: "Rec Movie")

    with_stubbed_singleton_method(Watchlist, :mixed_recommendations_for, ->(*_args, **_opts) { { items: [ rec_movie ], sources: [], based_on_high_ratings: true } }) do
      get watchlists_path(tab: "recommendations"), headers: NATIVE_ANDROID_HEADERS
      assert_response :success
      assert_select "turbo-frame#watchlists_content.block[target='_top']", count: 1
      assert_select "turbo-frame#watchlists_content[data-turbo-action]", count: 0
      assert_select "turbo-frame#watchlists_content a[href='#{watchlists_path(tab: 'recommendations', source_id: 'all')}'][data-turbo-frame='watchlists_content']", count: 1
      assert_select "select#recommendation_source_select[onchange*=\"frame: 'watchlists_content'\"]", count: 1
    end
  end
end
