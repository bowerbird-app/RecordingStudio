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

  private

  def load_recording
    @recording = ControlRoom::Recording.find(params[:id])
  end
end
