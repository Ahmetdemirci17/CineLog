class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :failure

  def google_oauth2
    @user = User.from_omniauth(request.env['omniauth.auth'])

    if @user.persisted?
      flash[:notice] = I18n.t 'devise.omniauth_callbacks.success', kind: 'Google', default: 'Google ile başarıyla giriş yapıldı.'
      sign_in_and_redirect @user, event: :authentication
    else
      session['devise.google_data'] = request.env['omniauth.auth'].except('extra')
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n").presence || "Google ile hesap oluşturulamadı."
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
