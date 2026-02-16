class RecordingsController < ApplicationController
  def index
    @recordings = RecordingStudio::Recording
      .including_trashed
      .includes(:recordable, :root_recording, :events)
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
      impersonator: Current.impersonator,
      metadata: { source: "demo" }
    )

    redirect_to recording_path(@recording)
  end

  def revert
    recordable_type = @recording.recordable_type.to_s
    unless RecordingStudio.configuration.recordable_types.include?(recordable_type)
      raise ActiveRecord::RecordNotFound
    end

    recordable_class = recordable_type.safe_constantize
    raise ActiveRecord::RecordNotFound unless recordable_class

    recordable = recordable_class.find(params[:recordable_id])

    @recording = @recording.root_recording.revert(
      @recording,
      to_recordable: recordable,
      actor: current_actor,
      impersonator: Current.impersonator,
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
