class WorkspacesController < ApplicationController
  def index
    @workspaces = Workspace.order(created_at: :desc)
  end

  def show
    @workspace = Workspace.find(params[:id])
    @root_recording = root_recording_for(@workspace)
    @recordings = @root_recording.recordings_query(include_children: true)
      .includes(:recordable)
      .order(created_at: :asc)

    @recordings_by_parent = @recordings.group_by(&:parent_recording_id)
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = Workspace.new(workspace_params)

    if @workspace.save
      RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: @workspace, parent_recording_id: nil)
      redirect_to workspaces_path, notice: "Workspace created."
    else
      flash.now[:alert] = @workspace.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    # Trash functionality removed - now handled by RecordingStudio_trashable addon
    redirect_to workspaces_path, alert: "Delete functionality requires RecordingStudio_trashable addon"
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name)
  end
end
