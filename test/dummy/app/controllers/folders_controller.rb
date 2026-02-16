class FoldersController < ApplicationController
  before_action :set_recording, only: %i[show]
  before_action :authorize_view_folder!, only: %i[show]

  def index
    root_ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(actor: current_actor)

    @folders = RecordingStudio::Recording
      .where(recordable_type: "RecordingStudioFolder")
      .where(root_recording_id: root_ids)
      .includes(:recordable, :parent_recording, :root_recording)
  end

  def show
    @children = @recording.child_recordings.includes(:recordable)
    @boundary_recording = boundary_recording_for(@recording)
  end

  private

  def set_recording
    @recording = RecordingStudio::Recording
      .includes(:recordable, :root_recording, :parent_recording)
      .find(params[:recording_id])

    raise ActiveRecord::RecordNotFound unless @recording.recordable_type == "RecordingStudioFolder"
  end

  def boundary_recording_for(recording)
    RecordingStudio::Recording.unscoped
      .where(parent_recording_id: recording.id, recordable_type: "RecordingStudio::AccessBoundary", trashed_at: nil)
      .order(created_at: :desc, id: :desc)
      .first
  end

  def authorize_view_folder!
    require_recording_access!(@recording, minimum_role: :view)
  end
end
