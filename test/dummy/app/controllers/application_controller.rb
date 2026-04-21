class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  stale_when_importmap_changes if respond_to?(:stale_when_importmap_changes)

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :current_actor

  helper_method :current_actor

  private

  def root_recording_for(workspace)
    RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: workspace, parent_recording_id: nil)
  end

  def current_actor
    @current_actor ||= begin
      Current.actor = current_user
      Current.impersonator = nil
      current_user
    end
  end
end
