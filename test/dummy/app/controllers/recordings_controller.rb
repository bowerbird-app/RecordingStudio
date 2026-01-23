class RecordingsController < ApplicationController
  def index
    @recordings = RecordingStudio::Recording
      .including_trashed
      .includes(:recordable, :container, :events)
      .recent
  end

  before_action :load_recording, except: [:index]

  def show
    @events = @recording.events
    @recordables = ([@recording.recordable] + @events.flat_map { |event| [event.recordable, event.previous_recordable] })
      .compact
      .uniq { |recordable| recordable.id }
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
    @recording = RecordingStudio::Recording.including_trashed.find(recording_id)
  end
end
