class MobileAuthController < ApplicationController
  TOKEN_TTL = 2.minutes
  REPLAY_TTL = 5.minutes

  def start
    session[:mobile_oauth] = true
    render layout: false
  end

  def redeem
    if params[:error].present?
      redirect_to new_user_session_path, alert: "Google ile giriş iptal edildi veya tamamlanamadı."
      return
    end

    user = verify_mobile_oauth_token(params[:token])
    if user
      sign_in(:user, user)
      redirect_to root_path, notice: "Google ile başarıyla giriş yapıldı."
    else
      redirect_to new_user_session_path, alert: "Google kimlik doğrulama oturumu geçersiz veya süresi dolmuş."
    end
  end

  def self.generate_token_for(user)
    verifier.generate({ user_id: user.id, jti: SecureRandom.hex(16) }, expires_in: TOKEN_TTL)
  end

  def self.deep_link_url(token: nil, error: nil)
    query = token ? { token: token }.to_query : { error: error.presence || "failed" }.to_query
    "cinelog://auth/callback?#{query}"
  end

  def self.verifier
    Rails.application.message_verifier(:mobile_oauth)
  end

  private

  def verify_mobile_oauth_token(raw_token)
    return nil if raw_token.blank?

    payload = self.class.verifier.verified(raw_token.to_s)
    return nil unless payload.is_a?(Hash)

    user_id = payload[:user_id] || payload["user_id"]
    jti = payload[:jti] || payload["jti"]
    return nil if user_id.blank? || jti.blank?

    replay_key = "mobile_oauth_used:#{jti}"
    return nil if Rails.cache.exist?(replay_key)

    Rails.cache.write(replay_key, true, expires_in: REPLAY_TTL)
    User.find_by(id: user_id)
  end
end
