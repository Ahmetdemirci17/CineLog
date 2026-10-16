require "test_helper"

class Users::OmniauthCallbacksTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "successful google oauth logs in and redirects to root" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "123456789",
      info: {
        email: "cinelog_oauth@example.com",
        name: "Cine User"
      }
    )

    assert_difference("User.count", 1) do
      get user_google_oauth2_omniauth_callback_path
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  test "failed google oauth redirects to root with alert" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials

    get user_google_oauth2_omniauth_callback_path
    assert_redirected_to root_path
    follow_redirect!
    assert_not_nil flash[:alert]
  end

  test "sign in page sets no-store cache headers to prevent stale back-button login form" do
    get new_user_session_path
    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "stale CSRF token on POST /users/auth/google_oauth2 redirects cleanly instead of raising InvalidAuthenticityToken" do
    OmniAuth.config.test_mode = false
    ActionController::Base.allow_forgery_protection = true

    user = User.find_or_create_by!(email: "csrf_test@example.com") do |u|
      u.username = "csrf_tester"
      u.password = "password123"
      u.password_confirmation = "password123"
    end
    sign_in user

    post user_google_oauth2_omniauth_authorize_path, params: { authenticity_token: "stale_token_from_bfcache" }
    assert_redirected_to root_path
  ensure
    ActionController::Base.allow_forgery_protection = false
    OmniAuth.config.test_mode = true
  end
end
