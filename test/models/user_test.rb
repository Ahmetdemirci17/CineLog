require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "creates new user with valid username and provider/uid" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "987654321",
      info: {
        email: "newgoogleuser@example.com",
        name: "Ahmet Demirci"
      }
    )

    assert_difference("User.count", 1) do
      user = User.from_omniauth(auth)
      assert user.persisted?
      assert_equal "google_oauth2", user.provider
      assert_equal "987654321", user.uid
      assert_equal "newgoogleuser@example.com", user.email
      assert_equal "ahmet_demirci", user.username
    end
  end

  test "links existing user by email to google oauth" do
    existing = users(:one)
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "11223344",
      info: {
        email: existing.email,
        name: "Different Name"
      }
    )

    assert_no_difference("User.count") do
      user = User.from_omniauth(auth)
      assert_equal existing.id, user.id
      assert_equal "google_oauth2", user.reload.provider
      assert_equal "11223344", user.uid
    end
  end

  test "resolves username collision by appending suffix" do
    existing = users(:one) # username: user_one
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "998877",
      info: {
        email: "user_one_second@example.com",
        name: "user_one"
      }
    )

    user = User.from_omniauth(auth)
    assert user.persisted?
    assert_not_equal "user_one", user.username
    assert user.username.start_with?("user_one_")
  end
end
