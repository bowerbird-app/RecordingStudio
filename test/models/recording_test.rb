# frozen_string_literal: true

require "test_helper"

class RecordingTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[RecordingStudioPage RecordingStudioComment]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudioPage.delete_all
    RecordingStudioComment.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_scopes_filter_recordings
    workspace = Workspace.create!(name: "Workspace")
    first = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"),
                                    container: workspace).recording
    second = RecordingStudio.record!(action: "created", recordable: RecordingStudioComment.new(body: "Two"),
                                     container: workspace).recording

    second.update!(trashed_at: Time.current)

    assert_includes RecordingStudio::Recording.for_container(workspace), first
    refute_includes RecordingStudio::Recording.all, second
    assert_includes RecordingStudio::Recording.including_trashed, second
    assert_includes RecordingStudio::Recording.trashed, second
    assert_includes RecordingStudio::Recording.of_type(RecordingStudioPage), first
    assert_includes RecordingStudio::Recording.include_trashed, second
  end

  def test_events_filtering
    workspace = Workspace.create!(name: "Workspace")
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    created_at = 3.days.ago
    updated_at = 2.days.ago
    archived_at = 1.day.ago

    event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      container: workspace,
      actor: actor,
      occurred_at: created_at
    )
    recording = event.recording

    recording.log_event!(action: "updated", actor: actor, occurred_at: updated_at)
    recording.log_event!(action: "archived", actor: actor, occurred_at: archived_at)

    assert_equal 1, recording.events(actions: "created").count
    assert_equal 3, recording.events(actor: actor).count
    assert_equal 1, recording.events(from: archived_at).count
    assert_equal 2, recording.events(to: updated_at).count
    assert_equal 1, recording.events(limit: 1).count
  end

  def test_log_event_delegates_to_record
    workspace = Workspace.create!(name: "Workspace")
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"), container: workspace)
    recording = event.recording

    logged = recording.log_event!(action: "updated")

    assert_equal recording, logged.recording
    assert_equal "updated", logged.action
  end

  def test_log_event_supports_idempotency_and_timestamp
    workspace = Workspace.create!(name: "Workspace")
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"), container: workspace)
    recording = event.recording

    occurred_at = 5.minutes.ago
    logged = recording.log_event!(action: "reviewed", occurred_at: occurred_at, idempotency_key: "event-123")

    assert_equal "reviewed", logged.action
    assert_equal "event-123", logged.idempotency_key
    assert_in_delta occurred_at.to_f, logged.occurred_at.to_f, 1
  end

  def test_trash_delegates_to_container
    workspace = Workspace.create!(name: "Workspace")
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"), container: workspace)
    recording = event.recording

    recording.trash

    assert recording.reload.trashed_at
  end

  def test_recordings_count_updates_on_trash_and_restore
    workspace = Workspace.create!(name: "Workspace")
    page = RecordingStudioPage.new(title: "RecordingStudioPage")
    event = RecordingStudio.record!(action: "created", recordable: page, container: workspace)
    recording = event.recording

    page.reload
    assert_equal 1, page.recordings_count

    recording.update!(trashed_at: Time.current)
    page.reload
    assert_equal 0, page.recordings_count

    recording.update!(trashed_at: nil)
    page.reload
    assert_equal 1, page.recordings_count
  end

  def test_recordings_count_updates_when_recordable_changes
    workspace = Workspace.create!(name: "Workspace")
    first_recordable = RecordingStudioPage.create!(title: "First")
    event = RecordingStudio.record!(action: "created", recordable: first_recordable, container: workspace)
    recording = event.recording

    second_recordable = RecordingStudioPage.create!(title: "Second")
    RecordingStudio.record!(
      action: "updated",
      recordable: second_recordable,
      recording: recording,
      container: workspace
    )

    first_recordable.reload
    second_recordable.reload

    assert_equal 0, first_recordable.recordings_count
    assert_equal 1, second_recordable.recordings_count
  end

  def test_recordings_counter_skips_when_recordable_missing_column
    workspace = Workspace.create!(name: "Workspace")
    system_actor = SystemActor.create!(name: "Background task")

    recording = RecordingStudio::Recording.create!(container: workspace, recordable: system_actor)

    assert recording.persisted?
    refute_includes SystemActor.column_names, "recordings_count"

    recording.update!(trashed_at: Time.current)
    assert recording.reload.trashed_at
  end
end
