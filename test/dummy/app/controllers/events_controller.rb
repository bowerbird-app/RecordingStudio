class EventsController < ApplicationController
  def index
    @events = RecordingStudio::Event
      .preload(:recording, :recordable, :previous_recordable, :actor, :impersonator)
      .recent
  end
end
