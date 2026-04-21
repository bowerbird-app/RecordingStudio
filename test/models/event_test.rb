# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioPage]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudioPage.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_scopes_filter_events
    workspace = Workspace.create!(name: "Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    recording = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      root_recording: root_recording,
      parent_recording: root_recording,
      occurred_at: 3.days.ago
    ).recording

    created = recording.log_event!(action: "created", actor: actor, occurred_at: 2.days.ago)
    updated = recording.log_event!(action: "updated", actor: actor, occurred_at: 1.day.ago)

    assert_includes RecordingStudio::Event.for_recording(recording), created
    assert_includes RecordingStudio::Event.with_action("updated"), updated
    assert_equal 0, RecordingStudio::Event.by_actor(nil).count
    assert_equal 2, RecordingStudio::Event.by_actor(actor).count
    assert_equal updated.id, RecordingStudio::Event.recent.first.id
  end

  def test_events_count_updates_on_create_and_destroy
    workspace = Workspace.create!(name: "Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    page = RecordingStudioPage.new(title: "Test Page")
    event = RecordingStudio.record!(action: "created", recordable: page, root_recording: root_recording,
                                    parent_recording: root_recording)

    page.reload
    assert_equal 1, page.events_count

    event.destroy!
    page.reload
    assert_equal 0, page.events_count
  end

  def test_events_count_skips_when_recordable_missing_column
    workspace = Workspace.create!(name: "Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    system_actor = SystemActor.create!(name: "Background task")
    recording = RecordingStudio::Recording.create!(root_recording: root_recording, parent_recording: root_recording,
                                                   recordable: system_actor)

    event = RecordingStudio::Event.create!(
      action: "created",
      recordable: system_actor,
      recording: recording
    )

    assert event.persisted?
    assert_not_includes SystemActor.column_names, "events_count"
  end
end
