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
end
