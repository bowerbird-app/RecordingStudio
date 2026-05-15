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

    assert_includes RecordingStudio::Recording.for_root(root.id), first
    assert_includes RecordingStudio::Recording.all, second
    assert_includes RecordingStudio::Recording.of_type(RecordingStudioPage), first
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

  def test_subtree_events_include_self_and_filtered_descendants
    _, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    publishable_child = root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child Page" }
    comment_child = root.record(RecordingStudioComment, parent_recording: parent) do |comment|
      comment.body = "Child Comment"
    end

    parent.log_event!(action: "reviewed")
    publishable_child.log_event!(action: "published")
    comment_child.log_event!(action: "commented")

    events = parent.subtree_events(
      descendant_scope: ->(scope) { scope.where(recordable_type: "RecordingStudioPage") }
    )

    assert_equal %w[published reviewed created created], events.map(&:action)
    assert_equal [publishable_child.id, parent.id, publishable_child.id, parent.id], events.map(&:recording_id)
  end

  def test_subtree_events_support_filters_without_self
    _, root = create_workspace_root
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    child.log_event!(action: "published", actor: actor, occurred_at: 2.days.ago)
    child.log_event!(action: "reviewed", actor: actor, occurred_at: 1.day.ago)

    events = parent.subtree_events(
      include_self: false,
      descendant_scope: ->(scope) { scope.where(recordable_type: "RecordingStudioPage") },
      actions: "reviewed",
      actor: actor,
      from: 36.hours.ago,
      limit: 1
    )

    assert_equal 1, events.count
    assert_equal ["reviewed"], events.map(&:action)
    assert_equal [child.id], events.map(&:recording_id)
  end

  def test_latest_and_first_event_helpers
    _, root = create_workspace_root
    recording = root.record(RecordingStudioPage) { |page| page.title = "One" }

    created = recording.first_event
    recording.log_event!(action: "reviewed", occurred_at: 1.day.from_now)
    latest = recording.log_event!(action: "published", occurred_at: 2.days.from_now)

    assert_equal latest.id, recording.latest_event.id
    assert_equal created.id, recording.first_event.id
  end

  def test_recordables_returns_distinct_snapshots_for_a_recording
    _, root = create_workspace_root
    recording = root.record(RecordingStudioPage) { |page| page.title = "Draft" }
    original_snapshot = recording.recordable

    root.revise(recording) { |page| page.title = "Reviewed" }
    revised_snapshot = recording.reload.recordable
    recording.log_event!(action: "published")
    root.revert(recording, to_recordable: original_snapshot)

    assert_equal [original_snapshot.id, revised_snapshot.id], recording.recordables.map(&:id)
    assert_equal %w[Draft Reviewed], recording.recordables.map(&:title)
  end

  def test_event_by_idempotency_key_returns_matching_event
    _, root = create_workspace_root
    recording = root.record(RecordingStudioPage) { |page| page.title = "One" }
    logged = recording.log_event!(action: "published", idempotency_key: "publish-123")

    assert_equal logged.id, recording.event_by_idempotency_key("publish-123")&.id
    assert_nil recording.event_by_idempotency_key("missing")
    assert_nil recording.event_by_idempotency_key(nil)
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

  def test_tree_navigation_helpers
    _, root = create_workspace_root

    folder = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioFolder.new(name: "Projects"),
      root_recording: root,
      parent_recording: root
    ).recording
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Roadmap"),
      root_recording: root,
      parent_recording: folder
    ).recording
    comment = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioComment.new(body: "Looks good"),
      root_recording: root,
      parent_recording: page
    ).recording

    assert root.root?
    refute root.leaf?
    assert_equal 0, root.depth
    assert_equal 0, root.level
    assert_equal [], root.ancestors
    assert_equal [root], root.self_and_ancestors
    assert_equal [folder, page, comment], root.descendants
    assert_equal [root, folder, page, comment], root.self_and_descendants

    refute folder.root?
    refute folder.leaf?
    assert_equal 1, folder.depth
    assert_equal [root], folder.ancestors
    assert_equal [root, folder], folder.self_and_ancestors
    assert_equal [page, comment], folder.descendants

    assert_equal [root, folder], page.ancestors
    assert_equal [root, folder, page], page.self_and_ancestors
    assert_equal [comment], page.descendants

    assert comment.leaf?
    assert_equal 3, comment.depth
    assert_equal [root, folder, page], comment.ancestors
    assert_equal [root, folder, page, comment], comment.self_and_ancestors
    assert_equal [], comment.descendants
    assert_equal [comment], comment.self_and_descendants
    assert_equal [folder.id, page.id, comment.id], root.descendant_ids
    assert_equal [root.id, folder.id, page.id, comment.id], root.descendant_ids(include_self: true)
    assert_equal [root.id, folder.id, page.id, comment.id], root.subtree_recordings.map(&:id)
    assert_equal [folder.id, page.id, comment.id], root.subtree_recordings(include_self: false).map(&:id)
  end

  def test_subtree_recordings_accept_scope_and_order
    _, root = create_workspace_root

    folder = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioFolder.new(name: "Projects"),
      root_recording: root,
      parent_recording: root
    ).recording
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Roadmap"),
      root_recording: root,
      parent_recording: folder
    ).recording
    comment = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioComment.new(body: "Looks good"),
      root_recording: root,
      parent_recording: page
    ).recording

    assert_kind_of ActiveRecord::Relation, root.subtree_recordings
    assert_equal [comment.id], root.subtree_recordings(scope: ->(relation) { relation.where(id: comment.id) }).map(&:id)
    assert_equal [root.id, folder.id, page.id, comment.id].sort.reverse,
                 root.subtree_recordings(order: "id desc").map(&:id)
  end

  def test_lock_ids_normalizes_and_orders_ids
    _, root = create_workspace_root

    first = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      root_recording: root,
      parent_recording: root
    ).recording
    second = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Two"),
      root_recording: root,
      parent_recording: root
    ).recording
    third = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Three"),
      root_recording: root,
      parent_recording: root
    ).recording

    RecordingStudio::Recording.transaction do
      locked = RecordingStudio::Recording.lock_ids!([third.id, nil, second.id.to_s, first.id, third.id, -1])

      assert_equal [first.id, second.id, third.id].sort, locked.map(&:id)
    end
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

  def test_name_accessors_fall_back_to_typed_recordable_for_preloaded_root_recordings
    workspace, root = create_workspace_root(name: "Studio Workspace")

    RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioFolder.new(name: "Projects"),
      root_recording: root,
      parent_recording: root
    )

    folder_recording = RecordingStudio::Recording.includes(:recordable, :root_recording).find_by(
      recordable_type: "RecordingStudioFolder"
    )

    assert_equal workspace.recordable_name, folder_recording.root_recording.name
  end

  def test_name_falls_back_to_type_label_when_recordable_is_missing
    workspace, root = create_workspace_root(name: "Studio Workspace")

    Workspace.where(id: workspace.id).delete_all

    assert_equal "Workspace", root.reload.name
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
