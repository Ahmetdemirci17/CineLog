class AddRuntimeAndGenresToWatchlists < ActiveRecord::Migration[8.1]
  def change
    add_column :watchlists, :runtime, :integer
    add_column :watchlists, :genres, :string
  end
end
