# frozen_string_literal: true

require "test_helper"

class RecordingApiMethodsTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_dup_strategy = RecordingStudio.configuration.recordable_dup_strategy
    @original_include_children = RecordingStudio.configuration.include_children

    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioPage]
    RecordingStudio.configuration.recordable_dup_strategy = :dup
    RecordingStudio.configuration.include_children = false
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudioPage.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.recordable_dup_strategy = @original_dup_strategy
    RecordingStudio.configuration.include_children = @original_include_children
  end

  def test_record_creates_recording_and_event
    _, root_recording = create_workspace_root

    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }

    assert_equal "Draft", recording.recordable.title
    assert_equal "created", recording.events.first.action
  end

  def test_revise_creates_new_recordable_snapshot
    _, root_recording = create_workspace_root
    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }
    original_recordable_id = recording.recordable_id

    revised = root_recording.revise(recording) { |page| page.title = "Updated" }

    assert_not_equal original_recordable_id, revised.recordable_id
    assert_equal "updated", revised.events.first.action
  end

  def test_trash_and_restore_with_children
    _, root_recording = create_workspace_root
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    root_recording.trash(parent, include_children: true, impersonator: nil)

    assert parent.reload.trashed_at
    assert child.reload.trashed_at

    root_recording.restore(parent, include_children: true, impersonator: nil)

    assert_nil parent.reload.trashed_at
    assert_nil child.reload.trashed_at
  end

  def test_hard_delete_removes_recordings
    _, root_recording = create_workspace_root
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    root_recording.hard_delete(parent, include_children: true, impersonator: nil)

    assert_nil RecordingStudio::Recording.including_trashed.find_by(id: parent.id)
    assert_nil RecordingStudio::Recording.including_trashed.find_by(id: child.id)
  end

  def test_log_event_and_revert
    _, root_recording = create_workspace_root
    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }

    event = root_recording.log_event(recording, action: "reviewed")

    assert_equal "reviewed", event.action

    reverted = root_recording.revert(recording, to_recordable: recording.recordable)

    assert_equal "reverted", reverted.events.first.action
  end

  def test_log_event_records_impersonator
    _, root_recording = create_workspace_root
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    impersonator = User.create!(name: "Admin", email: "admin@example.com", password: "password123")
    recording = root_recording.record(RecordingStudioPage, actor: actor) { |page| page.title = "Draft" }

    event = root_recording.log_event(recording, action: "reviewed", actor: actor, impersonator: impersonator)

    assert_equal impersonator, event.impersonator
  end

  def test_recordings_filters_and_helpers
    _, root_recording = create_workspace_root
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    assert_equal 1, root_recording.recordings_query.count
    assert_equal 3, root_recording.recordings_query(include_children: true).count
    assert_equal 1, root_recording.recordings_of(RecordingStudioPage).count
    assert_equal 1, root_recording.recordings_query(include_children: true, parent_id: parent.id).count
    assert_equal parent.id,
                 root_recording.recordings_query(include_children: true, type: RecordingStudioPage,
                                                 recordable_order: "recording_studio_pages.title desc").first.id
  end

  def test_recordings_sanitizes_recordable_order
    _, root_recording = create_workspace_root
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "A" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Z" }

    set_timestamps!(first, updated_at: Time.current)
    set_timestamps!(second, updated_at: 1.minute.ago)

    recordings = root_recording.recordings_query(
      include_children: true,
      type: RecordingStudioPage,
      recordable_order: "recording_studio_pages.title desc; select * from users"
    )

    assert_equal [first.id, second.id], recordings.map(&:id)
  end

  def test_recordings_sanitizes_recordable_filters
    _, root_recording = create_workspace_root
    root_recording.record(RecordingStudioPage) { |page| page.title = "Alpha" }
    root_recording.record(RecordingStudioPage) { |page| page.title = "Beta" }

    filtered = root_recording.recordings_query(
      include_children: true,
      type: RecordingStudioPage,
      recordable_filters: { title: "Alpha" }
    )
    assert_equal 1, filtered.count

    unsafe = root_recording.recordings_query(
      include_children: true,
      type: RecordingStudioPage,
      recordable_filters: "recording_studio_pages.title = 'Alpha' OR 1=1"
    )
    assert_equal 2, unsafe.count
  end

  def test_recordings_order_ignores_unknown_columns
    _, root_recording = create_workspace_root
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "First" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Second" }

    set_timestamps!(first, updated_at: 1.minute.ago)
    set_timestamps!(second, updated_at: Time.current)

    recordings = root_recording.recordings_query(order: "nonexistent desc, updated_at asc")

    assert_equal [first.id, second.id], recordings.map(&:id)
  end

  def test_recordings_order_hash_sanitizes_columns
    _, root_recording = create_workspace_root
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "First" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Second" }

    set_timestamps!(first, updated_at: 1.minute.ago)
    set_timestamps!(second, updated_at: Time.current)

    recordings = root_recording.recordings_query(order: { updated_at: :asc, unknown: :desc })

    assert_equal [first.id, second.id], recordings.map(&:id)
  end

  def test_recordings_with_recordable_scope
    _, root_recording = create_workspace_root
    root_recording.record(RecordingStudioPage) { |page| page.title = "Alpha" }
    root_recording.record(RecordingStudioPage) { |page| page.title = "Beta" }

    recordings = root_recording.recordings_query(
      include_children: true,
      type: RecordingStudioPage,
      recordable_scope: ->(scope) { scope.where(recording_studio_pages: { title: "Alpha" }) }
    )

    assert_equal 1, recordings.count
  end

  def test_recordings_enforces_root_scope_after_custom_scope
    _, root_recording = create_workspace_root
    _, other_root = create_workspace_root(name: "Other Workspace")

    root = root_recording.record(RecordingStudioPage) { |page| page.title = "Root" }
    root_recording.record(RecordingStudioPage, parent_recording: root) { |page| page.title = "Child" }
    trashed = root_recording.record(RecordingStudioPage) { |page| page.title = "Trashed" }
    trashed.update!(trashed_at: Time.current)

    other_root.record(RecordingStudioPage) { |page| page.title = "Foreign" }

    recordings = root_recording.recordings_query(
      include_children: false,
      type: RecordingStudioPage,
      recordable_scope: lambda do |scope|
        scope.unscope(where: %i[root_recording_id parent_recording_id trashed_at])
      end
    )

    assert_equal [root.id], recordings.map(&:id)
  end

  def test_root_mutators_reject_foreign_recording
    _, root_recording = create_workspace_root
    _, other_root = create_workspace_root(name: "Other Workspace")

    local_recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Local" }
    foreign_recording = other_root.record(RecordingStudioPage) { |page| page.title = "Foreign" }

    assert_raises(ArgumentError) { root_recording.revise(foreign_recording) { |page| page.title = "Updated" } }
    assert_raises(ArgumentError) { root_recording.trash(foreign_recording) }
    assert_raises(ArgumentError) { root_recording.hard_delete(foreign_recording) }
    assert_raises(ArgumentError) { root_recording.restore(foreign_recording) }
    assert_raises(ArgumentError) { root_recording.log_event(foreign_recording, action: "reviewed") }
    assert_raises(ArgumentError) do
      root_recording.revert(foreign_recording, to_recordable: foreign_recording.recordable)
    end

    assert_nothing_raised do
      root_recording.log_event(local_recording, action: "reviewed")
    end
  end

  def test_recordings_with_recordable_filters_relation_and_arel
    _, root_recording = create_workspace_root
    root_recording.record(RecordingStudioPage) { |page| page.title = "Alpha" }
    root_recording.record(RecordingStudioPage) { |page| page.title = "Beta" }

    relation_filtered = root_recording.recordings_query(
      include_children: true,
      type: RecordingStudioPage,
      recordable_filters: RecordingStudioPage.where(title: "Alpha")
    )
    assert_equal 1, relation_filtered.count

    arel_filtered = root_recording.recordings_query(
      include_children: true,
      type: RecordingStudioPage,
      recordable_filters: RecordingStudioPage.arel_table[:title].eq("Beta")
    )
    assert_equal 1, arel_filtered.count
  end

  def test_recordings_limit_offset_and_date_filters
    _, root_recording = create_workspace_root
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "First" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Second" }
    third = root_recording.record(RecordingStudioPage) { |page| page.title = "Third" }

    set_timestamps!(first, created_at: 3.days.ago, updated_at: 3.days.ago)
    set_timestamps!(second, created_at: 2.days.ago, updated_at: 2.days.ago)
    set_timestamps!(third, created_at: 1.day.ago, updated_at: 1.day.ago)

    filters = {
      created_after: 4.days.ago,
      created_before: 12.hours.ago,
      updated_after: 3.days.ago,
      updated_before: 12.hours.ago,
      order: "created_at asc"
    }

    expected = root_recording.recordings_query(**filters).offset(1).limit(1).map(&:id)
    recordings = root_recording.recordings_query(**filters, limit: 1, offset: 1)

    assert_equal expected, recordings.map(&:id)
  end

  def test_recordings_ignores_invalid_type
    _, root_recording = create_workspace_root
    root_recording.record(RecordingStudioPage) { |page| page.title = "Alpha" }

    recordings = root_recording.recordings_query(type: "MissingType")

    assert_equal 0, recordings.count
  end

  def test_recordable_order_accepts_quoted_table
    _, root_recording = create_workspace_root
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "A" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Z" }

    recordings = root_recording.recordings_query(
      include_children: true,
      type: RecordingStudioPage,
      recordable_order: '"recording_studio_pages"."title" desc'
    )

    assert_equal [second.id, first.id], recordings.map(&:id)
  end

  def test_trash_uses_configuration_include_children
    _, root_recording = create_workspace_root
    RecordingStudio.configuration.include_children = true

    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    root_recording.trash(parent, impersonator: nil)

    assert parent.reload.trashed_at
    assert child.reload.trashed_at
  end

  def test_trash_restore_and_hard_delete_ignore_nil
    _, root_recording = create_workspace_root

    assert_nil root_recording.trash(nil, impersonator: nil)
    assert_nil root_recording.restore(nil, impersonator: nil)
    assert_nil root_recording.hard_delete(nil, impersonator: nil)
    assert_equal 0, RecordingStudio::Event.count
  end

  def test_custom_dup_strategy_used
    _, root_recording = create_workspace_root
    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }

    RecordingStudio.configuration.recordable_dup_strategy = lambda do |recordable|
      RecordingStudioPage.new(title: "Copy of #{recordable.title}")
    end

    revised = root_recording.revise(recording)

    assert_equal "Copy of Draft", revised.recordable.title
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    [workspace, root_recording]
  end

  def set_timestamps!(record, created_at: nil, updated_at: nil)
    original = record.class.record_timestamps
    record.class.record_timestamps = false
    attributes = {}
    attributes[:created_at] = created_at if created_at
    attributes[:updated_at] = updated_at if updated_at
    record.update!(attributes)
  ensure
    record.class.record_timestamps = original
  end
end
