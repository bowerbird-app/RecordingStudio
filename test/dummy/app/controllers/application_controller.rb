class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  impersonates :user

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :current_actor

  helper_method :current_actor, :impersonating?, :admin_user?, :service_account_options

  private

  def current_actor
    @current_actor ||= if impersonating?
      current_user
    else
      actor_from_session || current_user
    end
    Current.actor = @current_actor
    Current.impersonator = impersonating? ? true_user : nil
  end

  def impersonating?
    current_user.present? && current_user != true_user
  end

  def admin_user?
    true_user&.admin?
  end

  def require_admin!
    return if admin_user?

    redirect_to root_path, alert: "You are not authorized to impersonate."
  end

  def service_account_options
    ServiceAccount.order(:name)
  end

  def actor_from_key(value)
    type, id = value.to_s.split(":", 2)
    return if type.blank? || id.blank?

    type.constantize.find_by(id: id)
  rescue NameError
    nil
  end

  def actor_from_session
    return if session[:actor_type].blank? || session[:actor_id].blank?

    actor = actor_from_key("#{session[:actor_type]}:#{session[:actor_id]}")
    actor if actor.is_a?(ServiceAccount)
  end
end
