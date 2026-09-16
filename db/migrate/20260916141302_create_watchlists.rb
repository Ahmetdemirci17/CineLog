class CreateWatchlists < ActiveRecord::Migration[8.1]
  def change
    create_table :watchlists do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :tmdb_id, null: false
      t.string :media_type, null: false
      t.string :title, null: false
      t.string :poster_path
      t.integer :status, default: 0, null: false
      t.datetime :watched_at
      t.integer :user_rating

      t.timestamps
    end

    add_index :watchlists, [:user_id, :tmdb_id, :media_type], unique: true
  end
end
