require "test_helper"

class PwaTest < ActionDispatch::IntegrationTest
  test "manifest route returns valid json and correct content type" do
    get pwa_manifest_path(format: :json)
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "CineLog — Film & Dizi Takip", json["name"]
    assert_equal "CineLog", json["short_name"]
    assert_equal "standalone", json["display"]
    assert_equal "#0a0a0c", json["theme_color"]
    assert json["icons"].any? { |i| i["sizes"] == "512x512" }
    assert json["icons"].any? { |i| i["sizes"] == "192x192" }
  end

  test "static manifest.json file is accessible" do
    get "/manifest.json"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "CineLog", json["short_name"]
  end

  test "service worker route returns javascript" do
    get pwa_service_worker_path(format: :js)
    assert_response :success
    assert_match "cinelog-v1", response.body
    assert_match "addEventListener('install'", response.body
    assert_match "addEventListener('fetch'", response.body

    get "/service-worker.js"
    assert_response :success
    assert_match "cinelog-v1", response.body
  end

  test "application layout contains PWA meta and link tags" do
    get root_path
    assert_response :success
    assert_select 'link[rel="manifest"]'
    assert_select 'link[rel="apple-touch-icon"]'
    assert_select 'meta[name="theme-color"][content="#0a0a0c"]'
    assert_select 'meta[name="apple-mobile-web-app-capable"][content="yes"]'
    assert_select 'meta[name="apple-mobile-web-app-title"][content="CineLog"]'
  end
end
