# frozen_string_literal: true

class WorkspaceSwitchesController < ApplicationController
  def create
    workspace = Workspace.find(params[:workspace_id])
    root_recording = RecordingStudio::Recording.unscoped.find_by!(
      recordable: workspace,
      parent_recording_id: nil
    )

    switch_root_recording!(root_recording)

    redirect_to workspace_path(workspace), notice: "Switched to #{workspace.name}"
  rescue RecordingStudio::AccessDenied
    redirect_to workspaces_path, alert: "You don't have access to that workspace."
  end
end
