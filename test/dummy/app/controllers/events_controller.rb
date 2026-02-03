class EventsController < ApplicationController
  def index
    @events = RecordingStudio::Event
      .includes(:recording, :recordable, :previous_recordable, :actor, :impersonator)
      .recent
  end
end
