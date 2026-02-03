class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  impersonates :user

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :current_actor

  helper_method :current_actor, :impersonating?, :admin_user?, :system_actor_options

  private

  def current_actor
    actor, impersonator = resolve_actor_context

    @current_actor = actor
    Current.actor = actor
    Current.impersonator = impersonator
    actor
  end

  def resolve_actor_context
    system_actor = system_actor_from_session
    impersonated_user = impersonated_user_from_session

    if system_actor
      [system_actor, nil]
    else
      actor = impersonated_user || current_user
      impersonator = impersonated_user ? true_user : nil
      [actor, impersonator]
    end
  end

  def impersonating?
    impersonated_user_from_session.present?
  end

  def admin_user?
    true_user&.admin?
  end

  def require_admin!
    return if admin_user?

    redirect_to root_path, alert: "You are not authorized to impersonate."
  end

  def system_actor_options
    SystemActor.order(:name)
  end

  def impersonated_user_from_session
    return @impersonated_user_from_session if defined?(@impersonated_user_from_session)

    @impersonated_user_from_session = if session[:impersonated_user_id].present?
      User.find_by(id: session[:impersonated_user_id])
    end
  end

  def actor_from_key(value)
    type, id = value.to_s.split(":", 2)
    return if type.blank? || id.blank?

    type.constantize.find_by(id: id)
  rescue NameError
    nil
  end

  def system_actor_from_session
    return if session[:actor_type].blank? || session[:actor_id].blank?

    actor = actor_from_key("#{session[:actor_type]}:#{session[:actor_id]}")
    actor if actor.is_a?(SystemActor)
  end

  def actor_from_session
    system_actor_from_session
  end
end
