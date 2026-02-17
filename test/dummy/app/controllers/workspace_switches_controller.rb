# frozen_string_literal: true

class WorkspaceSwitchesController < ApplicationController
  def create
    workspace = Workspace.find(workspace_id_param)
    root_recording = RecordingStudio::Recording.unscoped.find_by!(
      recordable: workspace,
      parent_recording_id: nil
    )

    require_root_access!(root_recording, minimum_role: :view)

    switch_root_recording!(root_recording)

    redirect_to workspace_path(workspace), notice: "Switched to #{workspace.name}"
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound, RecordingStudio::AccessDenied
    redirect_to workspaces_path, alert: "You don't have access to that workspace."
  end

  private

  def workspace_id_param
    params.require(:workspace_id)
  end
end
