# frozen_string_literal: true

require "test_helper"

class RecordingListAndRecordablesTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(RecordingStudioFolder, RecordingStudioPage, RecordingStudioComment)
    @page_number = 0
    @folder_number = 0
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
  end

  def test_recordings_query_preloads_recordables_so_list_labels_stay_constant
    _, root = create_workspace_root
    seed_list(root, pages: 2, folders: 2)
    small_without, small_with = label_query_counts(root)
    assert_equal 5, root.recordings_query(include_children: true).count

    seed_list(root, pages: 18, folders: 17)
    large_without, large_with = label_query_counts(root)
    rows = root.recordings_query(include_children: true).to_a

    assert_equal 40, rows.size
    assert(rows.all? { |recording| recording.association(:recordable).loaded? })
    assert_includes rows.map(&:title), "Page 1"
    assert_includes rows.map(&:name), "📁 Folder 1"
    assert_operator large_without, :>, small_without
    assert_equal small_with, large_with
    assert_operator large_with, :<, large_without
  end

  def test_preloaded_missing_recordable_does_not_query_again_for_name
    _, root = create_workspace_root
    recording = root.record(RecordingStudioPage) { |page| page.title = "Gone" }
    RecordingStudioPage.where(id: recording.recordable_id).delete_all
    loaded = RecordingStudio::Recording.preload(:recordable).find(recording.id)

    queries = count_queries { assert_equal "Page", loaded.name }

    assert_equal 0, queries
    assert loaded.association(:recordable).loaded?
    assert_nil loaded.association(:recordable).target
  end

  def test_recordables_pages_oldest_first_with_a_keyset_cursor
    _, root = create_workspace_root
    recording = record_versions(root, count: 55)
    titles = (0..55).map { |index| "v#{index}" }

    page = recording.recordables
    assert_equal titles.first(50) + ["v55"], page.map(&:title)
    assert_equal RecordingStudio::Recording::RECORDABLES_LIMIT, page_event_count(recording, cursor: nil)
    assert page.next_cursor

    second = recording.recordables(cursor: page.next_cursor)
    assert_equal titles.last(7), second.map(&:title)
    assert_nil second.next_cursor

    assert_equal titles, recording.recordables(all: true).map(&:title)
    assert_nil recording.recordables(all: true).next_cursor

    full = recording.recordables(limit: 56)
    assert_equal titles, full.map(&:title)
    assert_empty recording.recordables(limit: 56, cursor: full.next_cursor)

    assert_raises(ArgumentError) { recording.recordables(all: true, limit: 10) }
    assert_raises(ArgumentError) { recording.recordables(all: true, cursor: page.next_cursor) }
    assert_raises(ArgumentError) { recording.recordables(cursor: "not-a-cursor") }
  end

  def test_recordables_cursor_breaks_ties_on_occurred_at_created_at_and_id
    _, root = create_workspace_root
    recording = record_versions(root, count: 2)
    stamp = Time.utc(2026, 3, 1, 8, 0, 0)
    RecordingStudio::Event.where(recording_id: recording.id).update_all(occurred_at: stamp, created_at: stamp)
    expected_ids = recording.events.reorder(occurred_at: :asc, created_at: :asc, id: :asc).pluck(:id)

    first = recording.recordables(limit: 1)
    assert_equal expected_ids.first.to_s, RecordingStudio::Event.cursor_point(first.next_cursor).last

    second = recording.recordables(limit: 1, cursor: first.next_cursor)
    assert_equal expected_ids.second.to_s, RecordingStudio::Event.cursor_point(second.next_cursor).last

    third = recording.recordables(limit: 1, cursor: second.next_cursor)
    assert_equal expected_ids.third.to_s, RecordingStudio::Event.cursor_point(third.next_cursor).last

    fourth = recording.recordables(limit: 1, cursor: third.next_cursor)
    assert_empty fourth
    assert_nil fourth.next_cursor
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.root_recording_for(workspace)]
  end

  def seed_list(root, pages:, folders:)
    pages.times do
      @page_number += 1
      title = "Page #{@page_number}"
      root.record(RecordingStudioPage) { |page| page.title = title }
    end
    folders.times do
      @folder_number += 1
      name = "Folder #{@folder_number}"
      root.record(RecordingStudioFolder) { |folder| folder.name = name }
    end
  end

  def label_query_counts(root)
    [unpreloaded_label_queries(root), preloaded_label_queries(root)]
  end

  def unpreloaded_label_queries(root)
    ids = root.recordings_query(include_children: true).pluck(:id)
    count_queries do
      RecordingStudio::Recording.where(id: ids).to_a.each do |recording|
        recording.name
        recording.title
      end
    end
  end

  def preloaded_label_queries(root)
    count_queries do
      root.recordings_query(include_children: true).to_a.each do |recording|
        recording.name
        recording.title
      end
    end
  end

  def count_queries(&block)
    count = 0
    callback = lambda { |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET |SHOW )/i)

      count += 1
    }
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    end
    count
  end

  def record_versions(root, count:)
    stamp = Time.utc(2026, 6, 1, 12, 0, 0)
    created = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "v0"),
      root_recording: root,
      parent_recording: root,
      occurred_at: stamp
    )
    recording = created.recording
    count.times do |index|
      RecordingStudio.record!(
        action: "updated",
        recordable: RecordingStudioPage.new(title: "v#{index + 1}"),
        recording: recording,
        root_recording: root,
        occurred_at: stamp + (index + 1).minutes
      )
    end
    recording.reload
  end

  def page_event_count(recording, cursor:)
    scope = recording.events.reorder(occurred_at: :asc, created_at: :asc, id: :asc)
    scope = scope.newer_than_cursor(cursor) if cursor.present?
    scope.limit(RecordingStudio::Recording::RECORDABLES_LIMIT).count
  end
end
