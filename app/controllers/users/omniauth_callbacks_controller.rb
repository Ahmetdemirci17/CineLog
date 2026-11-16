class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :failure

  def google_oauth2
    auth = request.env["omniauth.auth"]
    if auth.blank?
      redirect_to new_user_session_path, alert: "Google kimlik doğrulama bilgisi alınamadı."
      return
    end

    @user = User.from_omniauth(auth)

    if @user&.persisted?
      flash[:notice] = I18n.t "devise.omniauth_callbacks.success", kind: "Google", default: "Google ile başarıyla giriş yapıldı."
      sign_in_and_redirect @user, event: :authentication
    else
      session["devise.google_data"] = auth.respond_to?(:except) ? auth.except("extra") : nil
      alert_msg = @user&.errors&.full_messages&.join("\n").presence || "Google ile hesap oluşturulamadı."
      redirect_to new_user_registration_url, alert: alert_msg
    end
  end

  def failure
    if user_signed_in?
      redirect_to root_path, notice: "Oturumunuz zaten açık."
    else
      redirect_to root_path, alert: "Google ile giriş yapılırken bir hata oluştu veya işlem iptal edildi."
    end
  end
end
