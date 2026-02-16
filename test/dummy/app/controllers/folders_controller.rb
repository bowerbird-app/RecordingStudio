class FoldersController < ApplicationController
  before_action :set_recording, only: %i[show add_boundary remove_boundary]

  def index
    @folders = RecordingStudio::Recording
      .where(recordable_type: "RecordingStudioFolder")
      .includes(:recordable, :parent_recording, :root_recording)
  end

  def show
    @children = @recording.child_recordings.includes(:recordable)
    @boundary_recording = boundary_recording_for(@recording)
  end

  def add_boundary
    if boundary_recording_for(@recording)
      redirect_to folder_path(@recording), alert: "Boundary already exists."
      return
    end

    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: params[:minimum_role].presence)
    RecordingStudio::Recording.create!(
      root_recording: @recording.root_recording || @recording,
      recordable: boundary,
      parent_recording: @recording
    )

    redirect_to folder_path(@recording), notice: "Boundary added."
  end

  def remove_boundary
    boundary_recording = boundary_recording_for(@recording)

    unless boundary_recording
      redirect_to folder_path(@recording), alert: "Boundary not found."
      return
    end

    boundary_recording.recordable.destroy!
    boundary_recording.destroy!

    redirect_to folder_path(@recording), notice: "Boundary removed."
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
      .first
  end
end
