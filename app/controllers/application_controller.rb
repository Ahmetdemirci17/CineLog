class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :prevent_caching_on_auth_pages, if: :devise_controller?

  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_authenticity_token

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username])
  end

  private

  def prevent_caching_on_auth_pages
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end

  def handle_invalid_authenticity_token
    if user_signed_in?
      redirect_to root_path, notice: "Oturumunuz zaten açık."
    else
      redirect_to new_user_session_path, alert: "Sayfa süresi doldu, lütfen tekrar giriş yapın."
    end
  end
end
