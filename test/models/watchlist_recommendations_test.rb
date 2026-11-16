require "test_helper"

class WatchlistRecommendationsTest < ActiveSupport::TestCase
  class StubRecService
    attr_reader :requested_ids

    def initialize(mapping)
      @mapping = mapping
      @requested_ids = []
    end

    def movie_recommendations(tmdb_id, **)
      @requested_ids << [:movie, tmdb_id]
      { "results" => (@mapping[[:movie, tmdb_id]] || []).map(&:dup) }
    end

    def tv_recommendations(tmdb_id, **)
      @requested_ids << [:tv, tmdb_id]
      { "results" => (@mapping[[:tv, tmdb_id]] || []).map(&:dup) }
    end
  end

  setup do
    @user = User.create!(
      email: "rec_tester_#{SecureRandom.hex(4)}@example.com",
      username: "rec_user_#{SecureRandom.hex(4)}",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "mixed_recommendations_for blends recommendations across multiple high-rated items and ignores low-rated items" do
    # Avoid before_save TMDB call by providing runtime and genres
    @user.watchlists.create!(tmdb_id: 10, media_type: "movie", title: "Prestij", status: :watched, user_rating: 10, runtime: 130, genres: "Dram")
    @user.watchlists.create!(tmdb_id: 20, media_type: "movie", title: "Başlangıç", status: :watched, user_rating: 9, runtime: 148, genres: "Bilimkurgu")
    @user.watchlists.create!(tmdb_id: 30, media_type: "movie", title: "Kötü Film", status: :watched, user_rating: 3, runtime: 100, genres: "Aksiyon")
    @user.watchlists.create!(tmdb_id: 999, media_type: "movie", title: "Zaten Listede", status: :plan_to_watch, runtime: 110, genres: "Dram")

    stub_service = StubRecService.new({
      [:movie, 10] => [
        { "id" => 1001, "title" => "Sihirbaz", "vote_average" => 7.6, "vote_count" => 2500 },
        { "id" => 1002, "title" => "Akıl Defteri", "vote_average" => 8.2, "vote_count" => 14000 },
        { "id" => 999, "title" => "Zaten Listede", "vote_average" => 8.0, "vote_count" => 5000 }
      ],
      [:movie, 20] => [
        { "id" => 2001, "title" => "Zindan Adası", "vote_average" => 8.2, "vote_count" => 22000 },
        { "id" => 2002, "title" => "Kaynak Kod", "vote_average" => 7.5, "vote_count" => 9000 }
      ],
      [:movie, 30] => [
        { "id" => 3001, "title" => "Berbat Devam Filmi", "vote_average" => 5.1, "vote_count" => 800 }
      ]
    })

    result = Watchlist.mixed_recommendations_for(@user, service: stub_service, limit: 10)
    rec_ids = result[:items].map { |m| m["id"] }
    sources_used = result[:items].map { |m| m["_recommended_by"] }.uniq

    refute_includes stub_service.requested_ids, [:movie, 30], "Low-rated (3/10) movie must never be used as a recommendation source"
    refute_includes rec_ids, 3001, "Recommendations from low-rated movies must not appear"
    refute_includes rec_ids, 999, "Already watchlisted items must be excluded"

    assert_includes rec_ids, 1001
    assert_includes rec_ids, 2001
    assert_includes sources_used, "Prestij"
    assert_includes sources_used, "Başlangıç"
    assert_equal true, result[:based_on_high_ratings]
  end
end
