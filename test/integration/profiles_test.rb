require "test_helper"

class ProfilesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "cinephile@example.com",
      username: "cinephile",
      password: "password123"
    )
    @viewer = User.create!(
      email: "viewer@example.com",
      username: "viewer",
      password: "password123"
    )

    # Watched movies with ratings
    @watched_movie = Watchlist.create!(
      user: @user,
      tmdb_id: 100,
      media_type: "movie",
      title: "Interstellar",
      status: 1, # watched
      user_rating: 10,
      runtime: 169,
      genres: "Bilim Kurgu, Macera"
    )

    # Plan to watch movie
    @planned_movie = Watchlist.create!(
      user: @user,
      tmdb_id: 200,
      media_type: "movie",
      title: "Dune",
      status: 0, # plan_to_watch
      runtime: 155,
      genres: "Bilim Kurgu"
    )

    # Post
    @post = CommunityPost.create!(
      user: @user,
      title: "Interstellar hakkında düşüncelerim",
      content: "Nolan sinemasının zirvesi."
    )
  end

  test "guest can view public profile with stats and watched tab" do
    get user_profile_path(@user.username)
    assert_response :success
    assert_select "h1", text: /cinephile/
    assert_select "h4", text: /Interstellar/
  end

  test "profile handles case-insensitivity in username" do
    get "/u/#{@user.username.upcase}"
    assert_response :success
    assert_select "h1", text: /cinephile/
  end

  test "non-existent username redirects to root with alert" do
    get user_profile_path("non_existent_user_99999")
    assert_redirected_to root_path
    assert_equal "Kullanıcı bulunamadı.", flash[:alert]
  end

  test "can view plan_to_watch tab" do
    get user_profile_path(@user.username, tab: "plan_to_watch")
    assert_response :success
    assert_select "h4", text: /Dune/
  end

  test "can view favorites tab with high rated items" do
    get user_profile_path(@user.username, tab: "favorites")
    assert_response :success
    assert_select "h4", text: /Interstellar/
  end

  test "can view community posts tab" do
    get user_profile_path(@user.username, tab: "community")
    assert_response :success
    assert_select "h3", text: /Interstellar hakkında düşüncelerim/
  end

  test "calculates taste match score when viewer also rated shared movies" do
    # Viewer rates the same movie similarly
    Watchlist.create!(
      user: @viewer,
      tmdb_id: 100,
      media_type: "movie",
      title: "Interstellar",
      status: 1,
      user_rating: 9,
      runtime: 169,
      genres: "Bilim Kurgu, Macera"
    )

    sign_in @viewer
    get user_profile_path(@user.username)
    assert_response :success
    # Should display Zevk Uyumu and percentage (100 - (10-9)*15 = 85%)
    assert_includes response.body, "Zevk Uyumu"
    assert_includes response.body, "%85"
  end

  test "navbar user pill links to current user profile" do
    sign_in @viewer
    get root_path
    assert_response :success
    assert_select "a[href=?]", user_profile_path(@viewer.username)
  end

  test "community post links author to profile" do
    get community_posts_path
    assert_response :success
    assert_select "a[href=?]", user_profile_path(@user.username)
  end
end
