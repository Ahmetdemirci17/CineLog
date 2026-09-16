class CreateCommunityPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :community_posts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :content, null: false
      t.integer :tmdb_id
      t.string :media_type

      t.timestamps
    end

    add_index :community_posts, :tmdb_id
  end
end
