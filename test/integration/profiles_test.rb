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
    assert_select "span.text-emerald-400", text: /İzlendi/
    assert_select "span.text-amber-400", text: /İzlenecek/, count: 0
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
    assert_select "span.text-amber-400", text: /İzlenecek/
    assert_select "span.text-emerald-400", text: /İzlendi/, count: 0
  end

  test "can view favorites tab ordered by highest rating first while watched tab preserves watched_at order" do
    @watched_movie.update!(watched_at: 3.days.ago)
    Watchlist.create!(
      user: @user,
      tmdb_id: 300,
      media_type: "movie",
      title: "Arrival",
      status: 1,
      user_rating: 9,
      watched_at: 1.hour.ago,
      runtime: 116,
      genres: "Bilim Kurgu"
    )

    # 1. Favorites tab orders by user_rating DESC (Interstellar 10 before Arrival 9)
    get user_profile_path(@user.username, tab: "favorites")
    assert_response :success
    assert_select "h4", text: /Interstellar/
    assert_select "h4", text: /Arrival/
    assert_operator response.body.index("Interstellar"), :<, response.body.index("Arrival")

    # 2. Watched tab top showcase (@favorites) orders by user_rating DESC, while main grid (@watchlists) orders by watched_at DESC
    get user_profile_path(@user.username, tab: "watched")
    assert_response :success
    showcase_titles = css_select("div.p-2\\.5 span.font-bold").map { |el| el.text.strip }
    assert_equal ["Interstellar", "Arrival"], showcase_titles

    grid_titles = css_select("h4 a").map { |el| el.text.strip }
    assert_equal ["Arrival", "Interstellar"], grid_titles
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
    get community_posts_path
    assert_response :success
    assert_select "a[href=?]", user_profile_path(@viewer.username)
  end

  test "community post links author to profile" do
    get community_posts_path
    assert_response :success
    assert_select "a[href=?]", user_profile_path(@user.username)
    refute_includes response.body, "\#{"
    assert_select "nav a[href=?] svg.text-purple-400", community_posts_path
    assert_select "nav a[href=?] svg.text-zinc-400", root_path
  end

  test "profile page does not contain uninterpolated ruby expressions in HTML and applies active tab badge classes" do
    get user_profile_path(@user.username)
    assert_response :success
    refute_includes response.body, "\#{"
    assert_select "a[href=?] span.bg-purple-800.text-white", user_profile_path(@user.username, tab: "watched")
    assert_select "a[href=?] span.bg-zinc-800.text-zinc-400", user_profile_path(@user.username, tab: "plan_to_watch")
  end

  test "author can delete their own community post" do
    sign_in @user
    assert_difference("CommunityPost.count", -1) do
      delete community_post_path(@post)
    end
    assert_redirected_to community_posts_path
    assert_equal "Konu silindi.", flash[:notice]
  end

  test "non-author cannot delete another user community post" do
    sign_in @viewer
    assert_no_difference("CommunityPost.count") do
      delete community_post_path(@post)
    end
    assert_redirected_to community_posts_path
    assert_equal "Bu işlem için yetkiniz yok.", flash[:alert]
  end
end
