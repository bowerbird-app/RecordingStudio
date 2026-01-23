class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :current_actor

  helper_method :current_actor, :actor_options, :current_actor_key

  private

  def current_actor
    @current_actor ||= current_user || actor_from_session
    Current.actor = @current_actor
  end

  def current_actor_key
    actor_key(current_actor)
  end

  def actor_options
    users = User.order(:name).map { |user| ["#{user.name} (User)", actor_key(user)] }
    services = ServiceAccount.order(:name).map { |service| ["#{service.name} (Service)", actor_key(service)] }
    users + services
  end

  def actor_key(actor)
    return nil unless actor

    "#{actor.class.name}:#{actor.id}"
  end

  def actor_from_key(value)
    type, id = value.to_s.split(":", 2)
    return if type.blank? || id.blank?

    type.constantize.find_by(id: id)
  rescue NameError
    nil
  end

  def actor_from_session
    actor_from_key("#{session[:actor_type]}:#{session[:actor_id]}")
  end
end
