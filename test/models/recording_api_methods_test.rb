# frozen_string_literal: true

require "test_helper"

class RecordingApiMethodsTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_dup_strategy = RecordingStudio.configuration.recordable_dup_strategy

    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioPage RecordingStudioComment]
    RecordingStudio.configuration.recordable_dup_strategy = :dup
    RecordingStudio::DelegatedTypeRegistrar.apply!

    reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioComment)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.recordable_dup_strategy = @original_dup_strategy
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

  def test_root_lookup_helpers_find_recordings_and_recordables
    _, root_recording = create_workspace_root
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "Alpha" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Beta" }

    assert_equal first.id, root_recording.recording_for(first.recordable)&.id
    assert_equal [second.id, first.id], root_recording.recordings_for([second.recordable, first.recordable]).map(&:id)
    assert_equal [second.recordable.id],
                 root_recording.recordables_of(RecordingStudioPage, recordable_filters: { title: "Beta" }).map(&:id)
  end

  def test_child_recordings_of_filters_direct_children_for_parent
    _, root_recording = create_workspace_root
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
    root_recording.record(RecordingStudioPage) { |page| page.title = "Sibling" }

    assert_equal [child.id], root_recording.child_recordings_of(parent).map(&:id)
  end

  def test_recordings_with_children_returns_distinct_parents_with_matching_child_type
    _, root_recording = create_workspace_root
    matching_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Matching" }
    other_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Other" }

    root_recording.record(RecordingStudioComment, parent_recording: matching_parent) do |comment|
      comment.body = "First matching child"
    end
    root_recording.record(RecordingStudioComment, parent_recording: matching_parent) do |comment|
      comment.body = "Second matching child"
    end
    root_recording.record(RecordingStudioPage, parent_recording: other_parent) { |page| page.title = "Child page" }

    recordings = root_recording.recordings_with_children(
      type: RecordingStudioPage,
      child_type: RecordingStudioComment,
      order: { updated_at: :asc }
    )

    assert_equal [matching_parent.id], recordings.map(&:id)
  end

  def test_recordings_with_children_supports_child_recordable_filters
    _, root_recording = create_workspace_root
    published_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Published Parent" }
    draft_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft Parent" }

    root_recording.record(RecordingStudioComment, parent_recording: published_parent) do |comment|
      comment.body = "Published"
    end
    root_recording.record(RecordingStudioComment, parent_recording: draft_parent) do |comment|
      comment.body = "Draft"
    end

    recordings = root_recording.recordings_with_children(
      type: RecordingStudioPage,
      child_type: RecordingStudioComment,
      child_recordable_filters: { body: "Published" }
    )

    assert_equal [published_parent.id], recordings.map(&:id)
  end

  def test_recordings_with_descendants_returns_parents_with_matching_descendant_type
    _, root_recording = create_workspace_root
    matching_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Ancestor" }
    intermediate = root_recording.record(
      RecordingStudioPage,
      parent_recording: matching_parent
    ) { |page| page.title = "Intermediate" }
    other_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Other" }

    root_recording.record(RecordingStudioComment, parent_recording: intermediate) do |comment|
      comment.body = "Nested match"
    end
    root_recording.record(RecordingStudioPage, parent_recording: other_parent) { |page| page.title = "Leaf" }

    recordings = root_recording.recordings_with_descendants(
      type: RecordingStudioPage,
      descendant_type: RecordingStudioComment,
      order: { updated_at: :asc }
    )

    assert_equal [matching_parent.id, intermediate.id], recordings.map(&:id)
  end

  def test_recordings_with_descendants_supports_descendant_recordable_filters
    _, root_recording = create_workspace_root
    published_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Published Parent" }
    published_child = root_recording.record(
      RecordingStudioPage,
      parent_recording: published_parent
    ) { |page| page.title = "Published Child" }
    draft_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft Parent" }
    draft_child = root_recording.record(
      RecordingStudioPage,
      parent_recording: draft_parent
    ) { |page| page.title = "Draft Child" }

    root_recording.record(RecordingStudioComment, parent_recording: published_child) do |comment|
      comment.body = "Published"
    end
    root_recording.record(RecordingStudioComment, parent_recording: draft_child) do |comment|
      comment.body = "Draft"
    end

    recordings = root_recording.recordings_with_descendants(
      type: RecordingStudioPage,
      descendant_type: RecordingStudioComment,
      descendant_recordable_filters: { body: "Published" }
    )

    assert_equal [published_child.id, published_parent.id], recordings.map(&:id)
  end

  def test_recordings_without_children_returns_parents_without_matching_child_type
    _, root_recording = create_workspace_root
    comment_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Comment Parent" }
    page_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Page Parent" }
    empty_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Empty Parent" }

    root_recording.record(RecordingStudioComment, parent_recording: comment_parent) do |comment|
      comment.body = "Has comment child"
    end
    page_child = root_recording.record(
      RecordingStudioPage,
      parent_recording: page_parent
    ) { |page| page.title = "Has page child" }

    recordings = root_recording.recordings_without_children(
      type: RecordingStudioPage,
      child_type: RecordingStudioComment,
      order: { updated_at: :asc }
    )

    assert_equal [page_parent.id, empty_parent.id, page_child.id], recordings.map(&:id)
  end

  def test_recordings_without_children_supports_child_recordable_filters
    _, root_recording = create_workspace_root
    published_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Published Parent" }
    draft_parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft Parent" }

    root_recording.record(RecordingStudioComment, parent_recording: published_parent) do |comment|
      comment.body = "Published"
    end
    root_recording.record(RecordingStudioComment, parent_recording: draft_parent) do |comment|
      comment.body = "Draft"
    end

    recordings = root_recording.recordings_without_children(
      type: RecordingStudioPage,
      child_type: RecordingStudioComment,
      child_recordable_filters: { body: "Published" }
    )

    assert_equal [draft_parent.id], recordings.map(&:id)
  end

  def test_events_query_filters_root_timeline_by_recording_scope_and_action
    _, root_recording = create_workspace_root
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    parent.log_event!(action: "reviewed", actor: actor, occurred_at: 2.days.ago)
    child.log_event!(action: "published", actor: actor, occurred_at: 1.day.ago)

    events = root_recording.events_query(
      parent_id: parent.id,
      actions: "published",
      actor: actor,
      recordable_filters: { title: "Child" }
    )

    assert_equal [child.id], events.map(&:recording_id)
    assert_equal ["published"], events.map(&:action)
  end

  def test_recordings_with_events_returns_distinct_recordings_matching_event_filters
    _, root_recording = create_workspace_root
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "First" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Second" }

    first.log_event!(action: "published", actor: actor, occurred_at: 2.days.ago)
    first.log_event!(action: "reviewed", actor: actor, occurred_at: 1.day.ago)
    second.log_event!(action: "reviewed", actor: actor, occurred_at: 12.hours.ago)

    recordings = root_recording.recordings_with_events(
      actions: "reviewed",
      actor: actor,
      order: { updated_at: :asc }
    )

    assert_equal [first.id, second.id], recordings.map(&:id)
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

    other_root.record(RecordingStudioPage) { |page| page.title = "Foreign" }

    recordings = root_recording.recordings_query(
      include_children: false,
      type: RecordingStudioPage,
      recordable_scope: lambda do |scope|
        scope.unscope(where: %i[root_recording_id parent_recording_id])
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

  def test_custom_dup_strategy_used
    _, root_recording = create_workspace_root
    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }

    RecordingStudio.configuration.recordable_dup_strategy = lambda do |recordable|
      RecordingStudioPage.new(title: "Revised #{recordable.title}")
    end

    revised = root_recording.revise(recording)

    assert_equal "Revised Draft", revised.recordable.title
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
