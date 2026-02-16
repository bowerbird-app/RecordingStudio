class ApplicationController < ActionController::Base
  ALLOWED_ACTOR_TYPES = {
    "User" => User,
    "SystemActor" => SystemActor
  }.freeze
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes if respond_to?(:stale_when_importmap_changes)

  impersonates :user

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :current_actor

  rescue_from RecordingStudio::AccessDenied, with: :handle_access_denied

  helper_method :current_actor, :impersonating?, :admin_user?, :system_actor_options

  private

  def require_root_access!(root_recording, minimum_role: :view)
    allowed_ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(
      actor: current_actor,
      minimum_role: minimum_role
    )

    raise RecordingStudio::AccessDenied unless allowed_ids.include?(root_recording.id)
  end

  def require_recording_access!(recording, minimum_role: :view)
    allowed = RecordingStudio::Services::AccessCheck.allowed?(
      actor: current_actor,
      recording: recording,
      role: minimum_role
    )

    raise RecordingStudio::AccessDenied unless allowed
  end

  def handle_access_denied
    respond_to do |format|
      format.html { render "shared/no_access", status: :forbidden }
      format.any { head :forbidden }
    end
  end

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
      [ system_actor, nil ]
    else
      actor = impersonated_user || current_user
      impersonator = impersonated_user ? true_user : nil
      [ actor, impersonator ]
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

    actor_class = ALLOWED_ACTOR_TYPES[type]
    return unless actor_class

    actor_class.find_by(id: id)
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
