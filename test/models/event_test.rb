# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioPage]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_scopes_filter_events
    workspace = Workspace.create!(name: "Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    impersonator = User.create!(name: "Admin", email: "admin@example.com", password: "password123")
    recording = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      root_recording: root_recording,
      parent_recording: root_recording,
      occurred_at: 3.days.ago
    ).recording

    created = recording.log_event!(action: "created", actor: actor, impersonator: impersonator, occurred_at: 2.days.ago,
                                   idempotency_key: "created-1")
    updated = recording.log_event!(action: "updated", actor: actor, impersonator: impersonator, occurred_at: 1.day.ago)

    other_root = RecordingStudio::Recording.create!(recordable: Workspace.create!(name: "Other Workspace"))
    other_recording = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Other"),
      root_recording: other_root,
      parent_recording: other_root,
      occurred_at: 12.hours.ago
    ).recording
    other_recording.log_event!(action: "updated", occurred_at: 6.hours.ago)

    assert_includes RecordingStudio::Event.for_recording(recording), created
    assert_equal 3, RecordingStudio::Event.for_root(root_recording).count
    refute_includes RecordingStudio::Event.for_root(root_recording), other_recording.events.first
    assert_includes RecordingStudio::Event.with_action("updated"), updated
    assert_equal 0, RecordingStudio::Event.by_actor(nil).count
    assert_equal 2, RecordingStudio::Event.by_actor(actor).count
    assert_equal 2, RecordingStudio::Event.by_impersonator(impersonator).count
    assert_equal 0, RecordingStudio::Event.by_impersonator(nil).count
    assert_equal [updated.id],
                 RecordingStudio::Event.for_root(root_recording)
                                       .between(36.hours.ago, 12.hours.ago)
                                       .pluck(:id)
    assert_equal updated.id, RecordingStudio::Event.for_root(root_recording).recent.first.id
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
