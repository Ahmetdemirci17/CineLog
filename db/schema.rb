# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_17_191448) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "community_posts", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "media_type"
    t.string "title", null: false
    t.integer "tmdb_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tmdb_id"], name: "index_community_posts_on_tmdb_id"
    t.index ["user_id"], name: "index_community_posts_on_user_id"
  end

  create_table "community_replies", force: :cascade do |t|
    t.bigint "community_post_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["community_post_id"], name: "index_community_replies_on_community_post_id"
    t.index ["user_id"], name: "index_community_replies_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.string "username", default: "", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "watchlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "genres"
    t.string "media_type", null: false
    t.string "poster_path"
    t.integer "runtime"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.integer "tmdb_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "user_rating"
    t.datetime "watched_at"
    t.index ["user_id", "tmdb_id", "media_type"], name: "index_watchlists_on_user_id_and_tmdb_id_and_media_type", unique: true
    t.index ["user_id"], name: "index_watchlists_on_user_id"
  end

  add_foreign_key "community_posts", "users"
  add_foreign_key "community_replies", "community_posts"
  add_foreign_key "community_replies", "users"
  add_foreign_key "watchlists", "users"
end
