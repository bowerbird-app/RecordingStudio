class ActorsController < ApplicationController
  before_action :require_admin!, only: [ :update, :switch ]

  def index
    user_rows = User.order(:name).map { |user| { name: user.name, email: user.email } }
    system_rows = SystemActor.order(:name).map { |actor| { name: actor.name, email: nil } }

    @actors = (user_rows + system_rows).sort_by { |row| row[:name].to_s.downcase }
  end

  def update
    actor_key = params[:actor_id] || params.dig(:actor, :actor_id)
    actor = actor_from_key(actor_key)

    if actor.is_a?(SystemActor)
      switch_to_system_actor(actor)
      redirect_back fallback_location: root_path, notice: "Switched to #{actor.name}."
    elsif actor_key.blank?
      clear_system_actor_session
      redirect_back fallback_location: root_path, notice: "Stopped acting as a system actor."
    else
      clear_system_actor_session
      redirect_back fallback_location: root_path, alert: "Unable to switch to that system actor."
    end
  end

  def switch
    selection = params[:actor_selection]
    type, id = selection.to_s.split(":", 2)

    case type
    when "User"
      user = User.find_by(id: id)

      if user.present? && user.id != true_user.id
        clear_system_actor_session
        impersonate_user(user)
        redirect_back fallback_location: root_path, notice: "Now impersonating #{user.name}."
      else
        redirect_back fallback_location: root_path, alert: "Unable to impersonate that user."
      end
    when "SystemActor"
      actor = actor_from_key(selection)

      if actor.is_a?(SystemActor)
        switch_to_system_actor(actor)
        redirect_back fallback_location: root_path, notice: "Switched to #{actor.name}."
      else
        redirect_back fallback_location: root_path, alert: "Unable to switch to that system actor."
      end
    else
      stop_impersonating_user if impersonating?
      clear_system_actor_session
      redirect_back fallback_location: root_path, notice: "Stopped impersonation and system actor mode."
    end
  end

  private

  def switch_to_system_actor(actor)
    stop_impersonating_user if impersonating?
    session[:actor_type] = actor.class.name
    session[:actor_id] = actor.id
  end

  def clear_system_actor_session
    session.delete(:actor_type)
    session.delete(:actor_id)
  end
end
