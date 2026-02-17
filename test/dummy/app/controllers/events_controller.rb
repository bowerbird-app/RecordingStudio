class EventsController < ApplicationController
  def index
    root_ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(actor: current_actor, minimum_role: :view)

    @events = RecordingStudio::Event
      .joins(:recording)
      .where(recording_studio_recordings: { root_recording_id: root_ids })
      .preload(:recording, :recordable, :previous_recordable, :actor, :impersonator)
      .recent
  end
end
