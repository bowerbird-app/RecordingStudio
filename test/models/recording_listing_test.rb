# frozen_string_literal: true

require "test_helper"

class RecordingListingTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
      RecordingStudioCover
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    RecordingStudio::RecordingFilters.reset!
    reset_recording_studio_tables!(RecordingStudioFolder, RecordingStudioPage, RecordingStudioComment)
  end

  def teardown
    RecordingStudio::RecordingFilters.reset!
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_within_a_root_uses_for_root_and_includes_the_whole_tree
    tree = build_tree
    sql = RecordingStudio::Recording.within(tree.fetch(:root)).to_sql

    assert_includes sql, tree.fetch(:root).id
    refute_includes sql, tree.fetch(:deep).id
    refute_match(/WITH RECURSIVE/i, sql)
    refute_includes sql, "recording_walk"

    ids = RecordingStudio::Recording.within(tree.fetch(:root)).pluck(:id)
    assert_equal tree.fetch(:in_root).map(&:id).sort, ids.sort
    refute_includes ids, tree.fetch(:other_page).id
  end

  def test_within_accepts_a_root_id
    tree = build_tree

    assert_equal RecordingStudio::Recording.within(tree.fetch(:root)).order(:id).pluck(:id),
                 RecordingStudio::Recording.within(tree.fetch(:root).id).order(:id).pluck(:id)
  end

  def test_within_a_nested_recording_joins_the_walk_and_keeps_that_subtree
    tree = build_tree
    folder = tree.fetch(:folder)
    sql = RecordingStudio::Recording.within(folder).to_sql

    assert_includes sql, "recording_walk"
    assert_match(/WITH RECURSIVE/i, sql)
    assert_includes sql, folder.id
    refute_includes sql, tree.fetch(:deep).id
    refute_includes sql, tree.fetch(:shallow).id
    refute_match(/\bIN\s*\(/i, sql)
    refute_match(/ORDER BY recording_walk\.depth/i, sql)
    assert_nil RecordingStudio::Recording.within(folder).subtree_seed

    ids = RecordingStudio::Recording.within(folder).pluck(:id)
    assert_equal [folder, tree.fetch(:shallow), tree.fetch(:sibling), tree.fetch(:deep)].map(&:id).sort, ids.sort
    refute_includes ids, tree.fetch(:root).id
    refute_includes ids, tree.fetch(:other_folder).id
    refute_includes ids, tree.fetch(:outside).id
    refute_includes ids, tree.fetch(:other_page).id
  end

  def test_within_includes_self_and_nested_depth_without_sibling_subtrees
    tree = build_tree
    shallow = tree.fetch(:shallow)

    ids = RecordingStudio::Recording.within(shallow).pluck(:id)
    assert_equal [shallow.id, tree.fetch(:deep).id].sort, ids.sort
    refute_includes ids, tree.fetch(:sibling).id
    refute_includes ids, tree.fetch(:folder).id
  end

  def test_within_by_id_matches_the_recording_and_unknown_ids_are_empty
    tree = build_tree
    folder = tree.fetch(:folder)

    assert_equal RecordingStudio::Recording.within(folder).order(:id).pluck(:id),
                 RecordingStudio::Recording.within(folder.id).order(:id).pluck(:id)
    assert_empty RecordingStudio::Recording.within(nil)
    assert_empty RecordingStudio::Recording.within("")
    assert_empty RecordingStudio::Recording.within("not-an-id")
    assert_empty RecordingStudio::Recording.within(SecureRandom.uuid)
    assert_empty RecordingStudio::Recording.within(nil).newest_first
  end

  def test_within_composes_with_of_type_kept_and_newest_first
    tree = build_tree
    folder = tree.fetch(:folder)
    skipped = tree.fetch(:sibling)
    register_skip(skipped)

    expected = [tree.fetch(:deep).id, tree.fetch(:shallow).id]
    from_within = RecordingStudio::Recording.within(folder).of_type(RecordingStudioPage).kept.newest_first.pluck(:id)
    from_kept = RecordingStudio::Recording.kept.of_type(RecordingStudioPage).within(folder).newest_first.pluck(:id)

    assert_equal expected, from_within
    assert_equal expected, from_kept
    refute_includes from_within, skipped.id
    refute_includes from_within, folder.id
    assert_nil RecordingStudio::Recording.within(folder).of_type(RecordingStudioPage).newest_first.subtree_seed
  end

  def test_within_ordering_is_not_replaced_by_the_walk_page_seed
    tree = build_tree
    folder = tree.fetch(:folder)

    newest = RecordingStudio::Recording.within(folder).newest_first.limit(1).to_a
    assert_equal [tree.fetch(:deep).id], newest.map(&:id)

    typed = RecordingStudio::Recording.within(folder).of_type(RecordingStudioPage).newest_first.limit(1).to_a
    assert_equal [tree.fetch(:deep).id], typed.map(&:id)

    seeded = folder.subtree_recordings
    assert_equal folder.id, seeded.subtree_seed.fetch(:recording_id)
    assert_equal true, seeded.subtree_seed.fetch(:include_self)
  end

  def test_keyset_pages_newest_first_and_breaks_created_at_ties_with_id
    root = create_workspace_root
    older = Time.utc(2026, 6, 1, 12, 0, 0)
    newer = Time.utc(2026, 6, 2, 12, 0, 0)
    pages = Array.new(5) do |index|
      root.record(RecordingStudioPage, parent_recording: root) { |page| page.title = "Page #{index}" }
    end
    pages.first(3).each { |page| page.update_columns(created_at: older) }
    pages.last(2).each { |page| page.update_columns(created_at: newer) }

    relation = RecordingStudio::Recording.within(root).of_type(RecordingStudioPage)
    expected = relation.newest_first.pluck(:id)
    assert_equal 5, expected.size
    assert_equal pages.last(2).map(&:id).sort, expected.first(2).sort

    collected = page_ids(relation, page_size: 2)
    assert_equal expected, collected

    middle = RecordingStudio::Recording.find(expected.second)
    cursor = RecordingStudio::Recording.cursor_for(middle)
    created_at, id = RecordingStudio::Recording.cursor_point(cursor)
    assert_equal middle.id, id
    assert_equal middle.created_at.iso8601(6), created_at.iso8601(6)

    newer_ids = relation.newest_first.newer_than_cursor(cursor).pluck(:id)
    older_ids = relation.newest_first.older_than_cursor(cursor).pluck(:id)
    assert_equal expected.first(1), newer_ids
    assert_equal expected.drop(2), older_ids
    refute_includes newer_ids + older_ids, middle.id

    tied = relation.newest_first.where(created_at: older).pluck(:id)
    assert_equal 3, tied.size
    tie_cursor = RecordingStudio::Recording.cursor_for(RecordingStudio::Recording.find(tied.first))
    assert_equal tied.drop(1), relation.newest_first.older_than_cursor(tie_cursor).where(created_at: older).pluck(:id)
  end

  def test_keyset_pages_a_nested_subtree_without_duplicating_rows
    tree = build_tree
    relation = RecordingStudio::Recording.within(tree.fetch(:folder)).of_type(RecordingStudioPage)
    expected = relation.newest_first.pluck(:id)

    assert_equal expected, page_ids(relation, page_size: 1)
    assert_equal expected.uniq, expected
  end

  def test_blank_cursors_do_not_filter_and_invalid_cursors_raise
    root = create_workspace_root
    page = root.record(RecordingStudioPage) { |record| record.title = "Only" }
    relation = RecordingStudio::Recording.within(root)

    assert_equal relation.newest_first.pluck(:id), relation.newest_first.older_than_cursor(nil).pluck(:id)
    assert_equal relation.newest_first.pluck(:id), relation.newest_first.older_than_cursor("").pluck(:id)

    error = assert_raises(ArgumentError) { RecordingStudio::Recording.older_than_cursor("not-a-cursor") }
    assert_equal "cursor is invalid", error.message
    assert_raises(ArgumentError) { RecordingStudio::Recording.newer_than_cursor("not-a-cursor") }
    assert_raises(ArgumentError) { RecordingStudio::Recording.cursor_point(encode_cursor({})) }
    assert_raises(ArgumentError) { RecordingStudio::Recording.cursor_point(encode_cursor([])) }
    assert_raises(ArgumentError) do
      RecordingStudio::Recording.cursor_point(encode_cursor("created_at" => "yesterday", "id" => page.id))
    end
    assert_raises(ArgumentError) do
      RecordingStudio::Recording.older_than_cursor(
        encode_cursor("created_at" => page.created_at.iso8601(6), "id" => "nope")
      )
    end

    missing = assert_raises(ArgumentError) { RecordingStudio::Recording.cursor_for(nil) }
    assert_equal "recording is required", missing.message
    unsaved = assert_raises(ArgumentError) { RecordingStudio::Recording.cursor_for(RecordingStudio::Recording.new) }
    assert_equal "recording must be saved", unsaved.message
  end

  def test_event_cursor_still_uses_the_shared_encoding
    root = create_workspace_root
    page = root.record(RecordingStudioPage) { |record| record.title = "Noted" }
    event = page.log_event!(action: "noted")
    cursor = RecordingStudio::Event.cursor_for(event)
    payload = JSON.parse(Base64.urlsafe_decode64(cursor))

    assert_equal %w[occurred_at created_at id], payload.keys
    assert_equal event.occurred_at.iso8601(6), payload.fetch("occurred_at")
    assert_equal event.created_at.iso8601(6), payload.fetch("created_at")
    point = RecordingStudio::Event.cursor_point(cursor)
    assert_equal event.occurred_at.iso8601(6), point[0].iso8601(6)
    assert_equal event.created_at.iso8601(6), point[1].iso8601(6)
    assert_equal event.id, point[2]
  end

  private

  def build_tree
    root = create_workspace_root
    other = create_workspace_root(name: "Other")
    folder = root.record(RecordingStudioFolder) { |record| record.name = "Folder A" }
    other_folder = root.record(RecordingStudioFolder) { |record| record.name = "Folder B" }
    shallow = root.record(RecordingStudioPage, parent_recording: folder) { |record| record.title = "Shallow" }
    sibling = root.record(RecordingStudioPage, parent_recording: folder) { |record| record.title = "Sibling" }
    deep = root.record(RecordingStudioPage, parent_recording: shallow) { |record| record.title = "Deep" }
    outside = root.record(RecordingStudioPage, parent_recording: other_folder) { |record| record.title = "Outside" }
    other_page = other.record(RecordingStudioPage) { |record| record.title = "Elsewhere" }

    stamp = Time.utc(2026, 4, 1, 9, 0, 0)
    folder.update_columns(created_at: stamp)
    shallow.update_columns(created_at: stamp + 1.hour)
    sibling.update_columns(created_at: stamp + 2.hours)
    deep.update_columns(created_at: stamp + 3.hours)
    other_folder.update_columns(created_at: stamp)
    outside.update_columns(created_at: stamp + 4.hours)

    {
      root: root,
      folder: folder,
      other_folder: other_folder,
      shallow: shallow.reload,
      sibling: sibling.reload,
      deep: deep.reload,
      outside: outside.reload,
      other_page: other_page,
      in_root: [root, folder, other_folder, shallow, sibling, deep, outside]
    }
  end

  def create_workspace_root(name: "Workspace")
    RecordingStudio.create_root_recording!(Workspace.create!(name: name))
  end

  def register_skip(recording)
    quoted_id = RecordingStudio::Recording.connection.quote(recording.id)
    RecordingStudio.register_recording_filter(
      :skip_one,
      sql: ->(table) { "#{table}.id <> #{quoted_id}" }
    ) { |recordings| recordings.where.not(id: recording.id) }
  end

  def page_ids(relation, page_size:)
    collected = []
    cursor = nil
    20.times do
      page = relation.newest_first
      page = page.older_than_cursor(cursor) if cursor
      rows = page.limit(page_size).to_a
      break if rows.empty?

      collected.concat(rows.map(&:id))
      cursor = RecordingStudio::Recording.cursor_for(rows.last)
    end
    collected
  end

  def encode_cursor(payload)
    Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
  end
end

class RecordingRootTypeIndexTest < ActiveSupport::TestCase
  def test_root_type_creation_index_orders_created_at_and_id_newest_first_with_no_where
    index = RecordingStudio::Recording.connection.indexes(:recording_studio_recordings).find do |candidate|
      candidate.name == "index_rs_recordings_on_root_type_created_at_id"
    end

    assert index
    assert_equal %w[root_recording_id recordable_type created_at id], Array(index.columns)
    assert_equal({ "created_at" => :desc, "id" => :desc }, index.orders)
    assert_nil index.where
    refute index.unique

    recordable_lookup = RecordingStudio::Recording.connection.indexes(:recording_studio_recordings).find do |candidate|
      candidate.name == "index_rs_recordings_on_root_and_recordable"
    end
    assert recordable_lookup
    assert_equal %w[root_recording_id recordable_type recordable_id], Array(recordable_lookup.columns)
  end
end
