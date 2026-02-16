# frozen_string_literal: true

require "test_helper"

class ImpersonationEventTest < ActiveSupport::TestCase
  def setup
    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudioPage.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def test_event_records_impersonator
    workspace = Workspace.create!(name: "Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    admin = User.create!(name: "Admin", email: "admin@example.com", password: "password123")
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")

    recording = root_recording.record(RecordingStudioPage, actor: actor, impersonator: admin,
                                                           metadata: { source: "test" }) do |page|
      page.title = "Hello"
    end

    event = recording.events.first

    assert_equal actor, event.actor
    assert_equal admin, event.impersonator
    assert_nil event.previous_recordable
  ensure
    Current.reset_all
  end
end
