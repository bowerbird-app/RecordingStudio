class FoldersController < ApplicationController
  before_action :set_recording, only: %i[show]

  def index
    @folders = RecordingStudio::Recording
      .where(recordable_type: "RecordingStudioFolder")
      .includes(:recordable, :parent_recording, :root_recording)
  end

  def show
    @children = @recording.child_recordings.includes(:recordable)
  end

  private

  def set_recording
    @recording = RecordingStudio::Recording
      .includes(:recordable, :root_recording, :parent_recording)
      .find(params[:recording_id])

    raise ActiveRecord::RecordNotFound unless @recording.recordable_type == "RecordingStudioFolder"
  end
end
