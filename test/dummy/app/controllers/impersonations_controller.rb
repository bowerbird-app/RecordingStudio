class ImpersonationsController < ApplicationController
  before_action :require_admin!

  def create
    user = User.find(params[:user_id])
    impersonate_user(user)
    session[:impersonated_user_id] = user.id
    redirect_to root_path
  end

  def destroy
    stop_impersonating_user
    session.delete(:impersonated_user_id)
    redirect_to root_path
  end
end
