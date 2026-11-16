class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern, unless: :hotwire_native_app?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :hotwire_native_app?, :turbo_native_app?

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :prevent_caching_on_auth_pages, if: :devise_controller?

  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_authenticity_token

  protected

  def hotwire_native_app?
    request.user_agent.to_s.match?(/(Turbo|Hotwire) Native/i)
  end
  alias_method :turbo_native_app?, :hotwire_native_app?

  def after_sign_in_path_for(resource)
    return turbo_recede_historical_location_url if hotwire_native_app?

    super
  end

  def after_sign_out_path_for(resource_or_scope)
    return turbo_refresh_historical_location_url if hotwire_native_app?

    super
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username])
  end

  private

  def sanitized_page(max: 500)
    params[:page].to_i.clamp(1, max)
  end

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
