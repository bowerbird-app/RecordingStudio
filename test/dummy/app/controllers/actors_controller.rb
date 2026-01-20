class ActorsController < ApplicationController
  def update
    actor = actor_from_key(params[:actor_id])

    if actor
      session[:actor_type] = actor.class.name
      session[:actor_id] = actor.id
    end

    redirect_back fallback_location: root_path
  end
end
