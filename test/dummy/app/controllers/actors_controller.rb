class ActorsController < ApplicationController
  before_action :require_admin!

  def update
    actor = actor_from_key(params[:actor_id])

    if actor.is_a?(ServiceAccount)
      session[:actor_type] = actor.class.name
      session[:actor_id] = actor.id
    end

    redirect_back fallback_location: root_path
  end
end
