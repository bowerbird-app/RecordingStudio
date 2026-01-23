class EventsController < ApplicationController
  def index
    @events = RecordingStudio::Event
      .includes(:recording, :recordable, :previous_recordable, :actor)
      .recent
  end
end
