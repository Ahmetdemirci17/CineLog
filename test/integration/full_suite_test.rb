require "test_helper"

class FullSuiteTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_or_create_by!(email: "suite_user@example.com") do |u|
      u.username = "suite_tester"
      u.password = "password123"
      u.password_confirmation = "password123"
    end
    @post = CommunityPost.first || @user.community_posts.create!(
      title: "Interstellar benzeri zihin yakan film önerisi?",
      content: "Zaman bükülmesi ve derin bilimkurgu temalı yapımlar arıyorum.",
      tmdb_id: 157336,
      media_type: "movie"
    )
  end

  test "public pages load successfully" do
    get root_path
    assert_response :success

    get root_path(tab: "popular")
    assert_response :success

    get root_path(tab: "trending")
    assert_response :success

    get root_path(tab: "tv")
    assert_response :success

    get movie_path(157336)
    assert_response :success

    get movie_path(496243)
    assert_response :success
    assert_includes response.body, "Parazit"
    refute_includes response.body, "Yıldızlararası"

    get tv_show_path(95557)
    assert_response :success

    get search_path, params: { query: "Interstellar" }
    assert_response :success

    get search_suggestions_path, params: { query: "Interstellar" }
    assert_response :success
    assert_includes response.body, "Interstellar"

    # Actor profile & search tests
    get person_path(10297)
    assert_response :success
    assert_includes response.body, "Matthew McConaughey"
    assert_includes response.body, "Filmografi"

    get search_path, params: { query: "Matthew McConaughey" }
    assert_response :success
    assert_includes response.body, "Oyuncular & Yönetmenler"
    assert_includes response.body, "Matthew McConaughey"

    get search_suggestions_path, params: { query: "Matthew" }
    assert_response :success
    assert_includes response.body, "Oyuncu"

    get genres_path
    assert_response :success
    assert_includes response.body, "Kataloğu"

    get genre_path(878)
    assert_response :success
    assert_includes response.body, "Bilimkurgu"

    get genre_path(878, page: 2, sort_by: "popularity.desc")
    assert_response :success
    assert_includes response.body, "Sayfa"

    get community_posts_path
    assert_response :success

    get community_post_path(@post)
    assert_response :success
  end

  test "guest redirected from protected routes" do
    get new_community_post_path
    assert_redirected_to new_user_session_path

    get watchlists_path
    assert_redirected_to new_user_session_path
  end

  test "user authentication, watchlist hotwire actions and replies" do
    # Sign in
    sign_in @user

    get watchlists_path
    assert_response :success

    get watchlists_path(tab: "watched")
    assert_response :success

    get new_community_post_path
    assert_response :success

    # Hotwire Turbo Stream Watchlist creation
    post watchlists_path, params: {
      watchlist: {
        tmdb_id: 27205,
        media_type: "movie",
        title: "Inception",
        poster_path: "/edv5CZvWj09upOsy2Y6IwDhK8bt.jpg",
        status: "plan_to_watch"
      }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"

    # Hotwire Turbo Stream Watchlist update to watched
    wl = @user.watchlists.find_by(tmdb_id: 27205)
    assert_not_nil wl
    patch watchlist_path(wl), params: {
      watchlist: {
        status: "watched",
        user_rating: 10
      }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
    assert_equal 10, wl.reload.user_rating
    assert_equal "watched", wl.status

    # Hotwire Turbo Stream Reply creation
    post community_post_community_replies_path(@post), params: {
      community_reply: { content: "Hotwire Turbo Stream ile harika bir öneri!" }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"

    # Delete Watchlist item
    delete watchlist_path(wl), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
    assert_nil @user.watchlists.find_by(tmdb_id: 27205)
  end
end
