class CreateCommunityReplies < ActiveRecord::Migration[8.1]
  def change
    create_table :community_replies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :community_post, null: false, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end
  end
end
