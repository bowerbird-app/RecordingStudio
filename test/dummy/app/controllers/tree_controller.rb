class TreeController < ApplicationController
  DISPLAYED_RECORDABLE_TYPES = [
    Workspace.name,
    RecordingStudioFolder.name,
    RecordingStudioPage.name
  ].freeze

  def index
    @recordings = RecordingStudio::Recording
      .where(recordable_type: DISPLAYED_RECORDABLE_TYPES)
      .includes(:recordable)
      .order(created_at: :asc)

    @recordings_by_parent = @recordings.group_by(&:parent_recording_id)
  end
end
