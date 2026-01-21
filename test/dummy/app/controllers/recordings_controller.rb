class RecordingsController < ApplicationController
  before_action :load_recording

  def show
    @events = @recording.events.recent
  end

  def log_event
    @recording.log_event!(
      action: "commented",
      actor: current_actor,
      metadata: { source: "demo" }
    )

    redirect_to recording_path(@recording)
  end

  def revert
    recordable_class = @recording.recordable_type.constantize
    recordable = recordable_class.find(params[:recordable_id])

    @recording = @recording.container.revert(
      @recording,
      to_recordable: recordable,
      actor: current_actor,
      metadata: { source: "ui", reverted_to_id: recordable.id }
    )

    redirect_to recording_path(@recording)
  end

  private

  def load_recording
    recording_id = params[:id] || params[:recording_id]
    @recording = ControlRoom::Recording.with_archived.find(recording_id)
  end
end
