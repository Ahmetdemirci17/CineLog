require "test_helper"

class ConfigurationsControllerTest < ActionDispatch::IntegrationTest
  NATIVE_IOS_HEADERS = { "User-Agent" => "Hotwire Native iOS; Turbo Native iOS" }.freeze
  NATIVE_ANDROID_HEADERS = { "User-Agent" => "Hotwire Native Android" }.freeze

  test "ios_v1 path configuration returns valid json" do
    get ios_v1_configurations_path

    assert_response :success
    assert_equal "application/json", response.media_type

    payload = response.parsed_body
    assert_kind_of Hash, payload["settings"]
    assert_kind_of Array, payload["rules"]

    modal_rule = payload["rules"].find { |rule| rule.dig("properties", "context") == "modal" }
    assert_not_nil modal_rule
    assert_includes modal_rule["patterns"], "/new$"
    assert_includes modal_rule["patterns"], "/edit$"
    assert_includes modal_rule["patterns"], "/users/sign_in"
    assert_includes modal_rule["patterns"], "/users/sign_up"
    assert_includes modal_rule["patterns"], "/community/new"
  end

  test "android_v1 path configuration returns valid json with fragment uris" do
    get android_v1_configurations_path

    assert_response :success
    assert_equal "application/json", response.media_type

    payload = response.parsed_body
    default_rule = payload["rules"].find { |rule| rule.dig("properties", "context") == "default" }
    modal_rule = payload["rules"].find { |rule| rule.dig("properties", "context") == "modal" }

    assert_equal "hotwire://fragment/web", default_rule.dig("properties", "uri")
    assert_equal "hotwire://fragment/web/modal/sheet", modal_rule.dig("properties", "uri")
  end

  test "viewport meta prevents mobile zoom and enables viewport-fit=cover" do
    get new_user_session_path

    assert_response :success
    assert_select "meta[name='viewport'][content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover']"
  end

  test "hotwire native hides auth navbar and google oauth, keeps mobile nav on main screens" do
    get root_path
    assert_response :success
    assert_select "nav", minimum: 1
    assert_select "footer", count: 1

    get root_path, headers: NATIVE_IOS_HEADERS
    assert_response :success
    assert_select "nav", minimum: 1
    assert_select "footer", count: 0

    get new_user_session_path
    assert_response :success
    assert_select "nav", minimum: 1
    assert_select "form[action='#{user_google_oauth2_omniauth_authorize_path}']", count: 1

    get new_user_session_path, headers: NATIVE_IOS_HEADERS
    assert_response :success
    assert_select "nav", count: 0
    assert_select "footer", count: 0
    assert_select "form[action='#{user_google_oauth2_omniauth_authorize_path}']", count: 0
    assert_select "a[href='#{mobile_auth_start_path}']", count: 1

    get new_user_password_path, headers: NATIVE_ANDROID_HEADERS
    assert_response :success
    assert_select "nav", count: 0
    assert_select "h2", text: "Şifremi Unuttum"
  end

  test "hotwire native custom tabs google oauth start and token redeem" do
    get mobile_auth_start_path
    assert_response :success
    assert_select "form#mobile-oauth-form[action='#{user_google_oauth2_omniauth_authorize_path}'][method='post']", count: 1

    user = users(:one)
    token = MobileAuthController.generate_token_for(user)

    get mobile_auth_redeem_path(token: token), headers: NATIVE_ANDROID_HEADERS
    assert_redirected_to root_path

    get mobile_auth_redeem_path(token: "invalid-token"), headers: NATIVE_ANDROID_HEADERS
    assert_redirected_to new_user_session_path

    get mobile_auth_redeem_path(error: "cancelled"), headers: NATIVE_ANDROID_HEADERS
    assert_redirected_to new_user_session_path
  end

  test "hotwire native devise sign in recedes modal" do
    user = users(:one)

    post user_session_path,
         params: { user: { email: user.email, password: "password123" } },
         headers: NATIVE_IOS_HEADERS

    assert_redirected_to turbo_recede_historical_location_url
  end

  test "hotwire native community post create recedes modal" do
    sign_in users(:one)

    assert_difference("CommunityPost.count", 1) do
      post community_posts_path,
           params: { community_post: { title: "Native Test", content: "Detaylı içerik" } },
           headers: NATIVE_ANDROID_HEADERS
    end

    assert_redirected_to turbo_recede_historical_location_url(notice: "Konunuz başarıyla paylaşıldı!")
  end
end
