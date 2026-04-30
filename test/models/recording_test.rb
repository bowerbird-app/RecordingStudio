# frozen_string_literal: true

require "test_helper"

class RecordingTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    reset_recording_studio_tables!(RecordingStudioFolder, RecordingStudioPage, RecordingStudioComment)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_scopes_filter_recordings
    _, root = create_workspace_root
    first = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"),
                                    root_recording: root, parent_recording: root).recording
    second = RecordingStudio.record!(action: "created", recordable: RecordingStudioComment.new(body: "Two"),
                                     root_recording: root, parent_recording: root).recording

    second.update!(trashed_at: Time.current)

    assert_includes RecordingStudio::Recording.for_root(root.id), first
    assert_not_includes RecordingStudio::Recording.all, second
    assert_includes RecordingStudio::Recording.including_trashed, second
    assert_includes RecordingStudio::Recording.trashed, second
    assert_includes RecordingStudio::Recording.of_type(RecordingStudioPage), first
    assert_includes RecordingStudio::Recording.include_trashed, second
  end

  def test_events_filtering
    _, root = create_workspace_root
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    created_at = 3.days.ago
    updated_at = 2.days.ago
    archived_at = 1.day.ago

    event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      root_recording: root,
      parent_recording: root,
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
    _, root = create_workspace_root
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"),
                                    root_recording: root, parent_recording: root)
    recording = event.recording

    logged = recording.log_event!(action: "updated")

    assert_equal recording, logged.recording
    assert_equal "updated", logged.action
  end

  def test_log_event_supports_idempotency_and_timestamp
    _, root = create_workspace_root
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"),
                                    root_recording: root, parent_recording: root)
    recording = event.recording

    occurred_at = 5.minutes.ago
    logged = recording.log_event!(action: "reviewed", occurred_at: occurred_at, idempotency_key: "event-123")

    assert_equal "reviewed", logged.action
    assert_equal "event-123", logged.idempotency_key
    assert_in_delta occurred_at.to_f, logged.occurred_at.to_f, 1
  end

  def test_trash_delegates_to_root
    _, root = create_workspace_root
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "One"),
                                    root_recording: root, parent_recording: root)
    recording = event.recording

    recording.trash

    assert recording.reload.trashed_at
  end

  def test_recordings_count_updates_on_trash_and_restore
    _, root = create_workspace_root
    page = RecordingStudioPage.new(title: "Test Page")
    event = RecordingStudio.record!(action: "created", recordable: page, root_recording: root, parent_recording: root)
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
    _, root = create_workspace_root
    first_recordable = RecordingStudioPage.create!(title: "First")
    event = RecordingStudio.record!(action: "created", recordable: first_recordable, root_recording: root,
                                    parent_recording: root)
    recording = event.recording

    second_recordable = RecordingStudioPage.create!(title: "Second")
    RecordingStudio.record!(
      action: "updated",
      recordable: second_recordable,
      recording: recording,
      root_recording: root
    )

    first_recordable.reload
    second_recordable.reload

    assert_equal 0, first_recordable.recordings_count
    assert_equal 1, second_recordable.recordings_count
  end

  def test_recordings_counter_skips_when_recordable_missing_column
    _, root = create_workspace_root
    system_actor = SystemActor.create!(name: "Background task")

    recording = RecordingStudio::Recording.create!(root_recording: root, parent_recording: root,
                                                   recordable: system_actor)

    assert recording.persisted?
    assert_not_includes SystemActor.column_names, "recordings_count"

    recording.update!(trashed_at: Time.current)
    assert recording.reload.trashed_at
  end

  def test_parent_recording_must_belong_to_same_root
    _, root = create_workspace_root
    _, other_root = create_workspace_root(name: "Other Workspace")

    parent = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Parent"),
      root_recording: root,
      parent_recording: root
    ).recording

    child = RecordingStudio::Recording.new(
      root_recording: other_root,
      recordable: RecordingStudioPage.create!(title: "Child"),
      parent_recording: parent
    )

    assert_not child.valid?
    assert_includes child.errors[:parent_recording_id], "must belong to the same root recording"
  end

  def test_parent_recording_rejects_cycles
    _, root = create_workspace_root

    parent = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Parent"),
      root_recording: root,
      parent_recording: root
    ).recording
    child = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Child"),
      root_recording: root,
      parent_recording: parent
    ).recording

    parent.parent_recording = child
    assert_not parent.valid?
    assert_includes parent.errors[:parent_recording_id], "cannot be itself or a descendant recording"

    child.parent_recording = child
    assert_not child.valid?
    assert_includes child.errors[:parent_recording_id], "cannot be itself or a descendant recording"
  end

  def test_name_accessors_use_current_recordable_and_root_recording
    workspace, root = create_workspace_root(name: "Studio Workspace")

    folder_recording = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioFolder.new(name: "Projects"),
      root_recording: root,
      parent_recording: root
    ).recording

    assert_equal workspace.recordable_name, root.name
    assert_equal Workspace.recordable_type_label, root.type_label
    assert_equal "📁 Projects", folder_recording.name
    assert_equal "Folder", folder_recording.type_label
    assert_equal "Projects", folder_recording.title
    assert_nil folder_recording.summary
    assert_equal root.name, folder_recording.root_recording.name
  end

  def test_label_remains_an_alias_for_name
    _workspace, root = create_workspace_root(name: "Studio Workspace")

    assert_equal root.name, root.label
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    root = RecordingStudio::Recording.create!(recordable: workspace)
    [workspace, root]
  end
end
