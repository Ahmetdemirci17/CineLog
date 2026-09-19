class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  has_many :watchlists, dependent: :destroy
  has_many :community_posts, dependent: :destroy
  has_many :community_replies, dependent: :destroy

  validates :username, presence: true, uniqueness: { case_sensitive: false },
                       format: { with: /\A[a-zA-Z0-9_]+\z/, message: "only letters, numbers, and underscores allowed" },
                       length: { minimum: 3, maximum: 30 }

  def self.from_omniauth(auth)
    # 1. Existing user with this provider & uid
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    # 2. Existing user with matching email -> link Google account
    user = find_by(email: auth.info.email)
    if user
      user.update(provider: auth.provider, uid: auth.uid)
      return user
    end

    # 3. Create new user with valid unique username and random password
    create do |u|
      u.provider = auth.provider
      u.uid = auth.uid
      u.email = auth.info.email
      u.password = Devise.friendly_token[0, 20]
      u.username = generate_unique_username(auth)
    end
  end

  def self.generate_unique_username(auth)
    raw_name = auth.info.name.to_s.presence || auth.info.email.to_s.split("@").first
    base = raw_name.parameterize(separator: "_").gsub(/[^a-zA-Z0-9_]/, "").downcase
    base = "user_#{SecureRandom.hex(3)}" if base.length < 3
    base = base[0...20]

    candidate = base
    suffix = 1
    while exists?(["lower(username) = ?", candidate.downcase])
      candidate = "#{base[0...18]}_#{suffix}"
      suffix += 1
    end
    candidate
  end
end
