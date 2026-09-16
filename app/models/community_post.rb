class CommunityPost < ApplicationRecord
  belongs_to :user
  has_many :community_replies, dependent: :destroy

  validates :title, presence: true, length: { minimum: 5, maximum: 200 }
  validates :content, presence: true, length: { minimum: 10 }
  validates :media_type, inclusion: { in: %w[movie tv] }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
end
