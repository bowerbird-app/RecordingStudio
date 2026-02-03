# frozen_string_literal: true

require "test_helper"

class HasRecordingsContainerTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_dup_strategy = RecordingStudio.configuration.recordable_dup_strategy
    @original_include_children = RecordingStudio.configuration.include_children

    RecordingStudio.configuration.recordable_types = ["Page"]
    RecordingStudio.configuration.recordable_dup_strategy = :dup
    RecordingStudio.configuration.include_children = false
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    Page.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.recordable_dup_strategy = @original_dup_strategy
    RecordingStudio.configuration.include_children = @original_include_children
  end

  def test_record_creates_recording_and_event
    workspace = Workspace.create!(name: "Workspace")

    recording = workspace.record(Page) { |page| page.title = "Draft" }

    assert_equal "Draft", recording.recordable.title
    assert_equal "created", recording.events.first.action
  end

  def test_revise_creates_new_recordable_snapshot
    workspace = Workspace.create!(name: "Workspace")
    recording = workspace.record(Page) { |page| page.title = "Draft" }
    original_recordable_id = recording.recordable_id

    revised = workspace.revise(recording) { |page| page.title = "Updated" }

    refute_equal original_recordable_id, revised.recordable_id
    assert_equal "updated", revised.events.first.action
  end

  def test_trash_and_restore_with_children
    workspace = Workspace.create!(name: "Workspace")
    parent = workspace.record(Page) { |page| page.title = "Parent" }
    child = workspace.record(Page, parent_recording: parent) { |page| page.title = "Child" }

    workspace.trash(parent, include_children: true)

    assert parent.reload.trashed_at
    assert child.reload.trashed_at

    workspace.restore(parent, include_children: true)

    assert_nil parent.reload.trashed_at
    assert_nil child.reload.trashed_at
  end

  def test_hard_delete_removes_recordings
    workspace = Workspace.create!(name: "Workspace")
    parent = workspace.record(Page) { |page| page.title = "Parent" }
    child = workspace.record(Page, parent_recording: parent) { |page| page.title = "Child" }

    workspace.hard_delete(parent, include_children: true)

    assert_nil RecordingStudio::Recording.including_trashed.find_by(id: parent.id)
    assert_nil RecordingStudio::Recording.including_trashed.find_by(id: child.id)
  end

  def test_log_event_and_revert
    workspace = Workspace.create!(name: "Workspace")
    recording = workspace.record(Page) { |page| page.title = "Draft" }

    event = workspace.log_event(recording, action: "reviewed")

    assert_equal "reviewed", event.action

    reverted = workspace.revert(recording, to_recordable: recording.recordable)

    assert_equal "reverted", reverted.events.first.action
  end

  def test_log_event_records_impersonator
    workspace = Workspace.create!(name: "Workspace")
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    impersonator = User.create!(name: "Admin", email: "admin@example.com", password: "password123")
    recording = workspace.record(Page, actor: actor) { |page| page.title = "Draft" }

    event = workspace.log_event(recording, action: "reviewed", actor: actor, impersonator: impersonator)

    assert_equal impersonator, event.impersonator
  end

  def test_recordings_filters_and_helpers
    workspace = Workspace.create!(name: "Workspace")
    parent = workspace.record(Page) { |page| page.title = "Parent" }
    workspace.record(Page, parent_recording: parent) { |page| page.title = "Child" }

    assert_equal 1, workspace.recordings.count
    assert_equal 2, workspace.recordings(include_children: true).count
    assert_equal 1, workspace.recordings_of(Page).count
    assert_equal 1, workspace.recordings(include_children: true, parent_id: parent.id).count
    assert_equal parent.id, workspace.recordings(include_children: true, type: Page, recordable_order: "pages.title desc").first.id
  end

  def test_recordings_sanitizes_recordable_order
    workspace = Workspace.create!(name: "Workspace")
    first = workspace.record(Page) { |page| page.title = "A" }
    second = workspace.record(Page) { |page| page.title = "Z" }

    first.update_column(:updated_at, Time.current)
    second.update_column(:updated_at, 1.minute.ago)

    recordings = workspace.recordings(
      include_children: true,
      type: Page,
      recordable_order: "pages.title desc; select * from users"
    )

    assert_equal [first.id, second.id], recordings.map(&:id)
  end

  def test_recordings_sanitizes_recordable_filters
    workspace = Workspace.create!(name: "Workspace")
    workspace.record(Page) { |page| page.title = "Alpha" }
    workspace.record(Page) { |page| page.title = "Beta" }

    filtered = workspace.recordings(
      include_children: true,
      type: Page,
      recordable_filters: { title: "Alpha" }
    )
    assert_equal 1, filtered.count

    unsafe = workspace.recordings(
      include_children: true,
      type: Page,
      recordable_filters: "pages.title = 'Alpha' OR 1=1"
    )
    assert_equal 2, unsafe.count
  end

  def test_recordings_order_ignores_unknown_columns
    workspace = Workspace.create!(name: "Workspace")
    first = workspace.record(Page) { |page| page.title = "First" }
    second = workspace.record(Page) { |page| page.title = "Second" }

    first.update_column(:updated_at, 1.minute.ago)
    second.update_column(:updated_at, Time.current)

    recordings = workspace.recordings(order: "nonexistent desc, updated_at asc")

    assert_equal [first.id, second.id], recordings.map(&:id)
  end

  def test_recordings_order_hash_sanitizes_columns
    workspace = Workspace.create!(name: "Workspace")
    first = workspace.record(Page) { |page| page.title = "First" }
    second = workspace.record(Page) { |page| page.title = "Second" }

    first.update_column(:updated_at, 1.minute.ago)
    second.update_column(:updated_at, Time.current)

    recordings = workspace.recordings(order: { updated_at: :asc, unknown: :desc })

    assert_equal [first.id, second.id], recordings.map(&:id)
  end

  def test_recordings_with_recordable_scope
    workspace = Workspace.create!(name: "Workspace")
    workspace.record(Page) { |page| page.title = "Alpha" }
    workspace.record(Page) { |page| page.title = "Beta" }

    recordings = workspace.recordings(
      include_children: true,
      type: Page,
      recordable_scope: ->(scope) { scope.where(pages: { title: "Alpha" }) }
    )

    assert_equal 1, recordings.count
  end

  def test_recordings_with_recordable_filters_relation_and_arel
    workspace = Workspace.create!(name: "Workspace")
    workspace.record(Page) { |page| page.title = "Alpha" }
    workspace.record(Page) { |page| page.title = "Beta" }

    relation_filtered = workspace.recordings(
      include_children: true,
      type: Page,
      recordable_filters: Page.where(title: "Alpha")
    )
    assert_equal 1, relation_filtered.count

    arel_filtered = workspace.recordings(
      include_children: true,
      type: Page,
      recordable_filters: Page.arel_table[:title].eq("Beta")
    )
    assert_equal 1, arel_filtered.count
  end

  def test_recordings_limit_offset_and_date_filters
    workspace = Workspace.create!(name: "Workspace")
    first = workspace.record(Page) { |page| page.title = "First" }
    second = workspace.record(Page) { |page| page.title = "Second" }
    third = workspace.record(Page) { |page| page.title = "Third" }

    first.update_columns(created_at: 3.days.ago, updated_at: 3.days.ago)
    second.update_columns(created_at: 2.days.ago, updated_at: 2.days.ago)
    third.update_columns(created_at: 1.day.ago, updated_at: 1.day.ago)

    filters = {
      created_after: 4.days.ago,
      created_before: 12.hours.ago,
      updated_after: 3.days.ago,
      updated_before: 12.hours.ago,
      order: "created_at asc"
    }

    expected = workspace.recordings(**filters).offset(1).limit(1).map(&:id)
    recordings = workspace.recordings(**filters, limit: 1, offset: 1)

    assert_equal expected, recordings.map(&:id)
  end

  def test_recordings_ignores_invalid_type
    workspace = Workspace.create!(name: "Workspace")
    workspace.record(Page) { |page| page.title = "Alpha" }

    recordings = workspace.recordings(type: "MissingType")

    assert_equal 0, recordings.count
  end

  def test_recordable_order_accepts_quoted_table
    workspace = Workspace.create!(name: "Workspace")
    first = workspace.record(Page) { |page| page.title = "A" }
    second = workspace.record(Page) { |page| page.title = "Z" }

    recordings = workspace.recordings(
      include_children: true,
      type: Page,
      recordable_order: '"pages"."title" desc'
    )

    assert_equal [second.id, first.id], recordings.map(&:id)
  end

  def test_trash_uses_configuration_include_children
    workspace = Workspace.create!(name: "Workspace")
    RecordingStudio.configuration.include_children = true

    parent = workspace.record(Page) { |page| page.title = "Parent" }
    child = workspace.record(Page, parent_recording: parent) { |page| page.title = "Child" }

    workspace.trash(parent)

    assert parent.reload.trashed_at
    assert child.reload.trashed_at
  end

  def test_trash_restore_and_hard_delete_ignore_nil
    workspace = Workspace.create!(name: "Workspace")

    assert_nil workspace.trash(nil)
    assert_nil workspace.restore(nil)
    assert_nil workspace.hard_delete(nil)
    assert_equal 0, RecordingStudio::Event.count
  end

  def test_custom_dup_strategy_used
    workspace = Workspace.create!(name: "Workspace")
    recording = workspace.record(Page) { |page| page.title = "Draft" }

    RecordingStudio.configuration.recordable_dup_strategy = lambda do |recordable|
      Page.new(title: "Copy of #{recordable.title}")
    end

    revised = workspace.revise(recording)

    assert_equal "Copy of Draft", revised.recordable.title
  end
end
