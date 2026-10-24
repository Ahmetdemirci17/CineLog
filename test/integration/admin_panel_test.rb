require "test_helper"

class AdminPanelTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email: "admin_tester@example.com",
      username: "admin_tester",
      password: "password123",
      admin: true
    )
    @regular_user = User.create!(
      email: "regular_user@example.com",
      username: "regular_user",
      password: "password123",
      admin: false
    )
    @post = CommunityPost.create!(
      user: @regular_user,
      title: "Test Post",
      content: "Harika bir film incelemesi."
    )
    @watchlist = Watchlist.create!(
      user: @regular_user,
      tmdb_id: 12345,
      media_type: "movie",
      title: "Inception",
      status: 1,
      user_rating: 9,
      runtime: 148,
      genres: "Bilim Kurgu, Aksiyon"
    )
  end

  test "unauthenticated user cannot access admin dashboard" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "regular user is redirected from admin dashboard with alert" do
    sign_in @regular_user
    get admin_root_path
    assert_redirected_to root_path
    assert_equal "Bu sayfaya erişim yetkiniz bulunmamaktadır.", flash[:alert]
  end

  test "admin user can access dashboard and see metrics" do
    sign_in @admin
    get admin_root_path
    assert_response :success
    assert_select "h1", "Yönetici Paneli"
    assert_match "Kullanıcılar", response.body
    assert_match "İzleme Kayıtları", response.body
    assert_match "Topluluk Gönderileri", response.body
    refute_includes response.body, "\#{"
    assert_select "a[href=?] svg.text-purple-400", admin_root_path
    assert_select "a[href=?] svg.text-zinc-500", admin_users_path
  end

  test "admin can view users list and toggle admin role" do
    sign_in @admin
    get admin_users_path
    assert_response :success
    assert_match @regular_user.username, response.body

    # Toggle regular_user to admin
    patch toggle_admin_admin_user_path(@regular_user)
    assert_redirected_to admin_users_path
    assert @regular_user.reload.admin?

    # Toggle back to regular user
    patch toggle_admin_admin_user_path(@regular_user)
    assert_redirected_to admin_users_path
    assert_not @regular_user.reload.admin?
  end

  test "admin cannot remove their own admin role" do
    sign_in @admin
    patch toggle_admin_admin_user_path(@admin)
    assert_redirected_to admin_user_path(@admin)
    assert_equal "Kendi yöneticilik yetkinizi değiştiremezsiniz.", flash[:alert]
    assert @admin.reload.admin?
  end

  test "admin can moderate community posts" do
    sign_in @admin
    get admin_community_posts_path
    assert_response :success
    assert_match @post.title, response.body

    assert_difference("CommunityPost.count", -1) do
      delete admin_community_post_path(@post)
    end
    assert_redirected_to admin_community_posts_path
  end

  test "admin can view and delete watchlists" do
    sign_in @admin
    get admin_watchlists_path
    assert_response :success
    assert_match @watchlist.title, response.body
    assert_select "span.text-emerald-300", text: "İzlendi"

    assert_difference("Watchlist.count", -1) do
      delete admin_watchlist_path(@watchlist)
    end
    assert_redirected_to admin_watchlists_path
  end
end
