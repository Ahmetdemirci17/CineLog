class Watchlist < ApplicationRecord
  belongs_to :user

  enum :status, { plan_to_watch: 0, watched: 1 }

  validates :tmdb_id, presence: true
  validates :media_type, presence: true, inclusion: { in: %w[movie tv] }
  validates :title, presence: true
  validates :user_rating, numericality: { only_integer: true, in: 1..10 }, allow_nil: true
  validates :tmdb_id, uniqueness: { scope: [:user_id, :media_type], message: "has already been added to your watchlist" }

  scope :plan_to_watch, -> { where(status: :plan_to_watch).order(created_at: :desc) }
  scope :watched, -> { where(status: :watched).order(watched_at: :desc, updated_at: :desc) }
end
