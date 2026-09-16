class CommunityReply < ApplicationRecord
  belongs_to :user
  belongs_to :community_post

  validates :content, presence: true, length: { minimum: 2 }

  scope :chronological, -> { order(created_at: :asc) }
end
