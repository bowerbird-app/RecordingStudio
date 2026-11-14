# frozen_string_literal: true

require "test_helper"

class TreeWalkTest < ActiveSupport::TestCase
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

  def test_descendant_and_ancestor_order
    _, root = create_workspace_root
    later = root.record(RecordingStudioPage) { |page| page.title = "Later" }
    earlier = root.record(RecordingStudioPage) { |page| page.title = "Earlier" }
    grandchild = root.record(RecordingStudioComment, parent_recording: later) { |comment| comment.body = "Nested" }
    ordered_children = [earlier.id, later.id].sort

    assert_equal ordered_children + [grandchild.id], root.descendant_ids
    assert_equal [root.id] + ordered_children + [grandchild.id], root.descendant_ids(include_self: true)
    assert_equal [grandchild.id, later.id, root.id], RecordingStudio::Tree.ancestor_ids(grandchild.id)
    assert_equal [later.id, root.id], RecordingStudio::Tree.ancestor_ids(later.id)
    assert_equal [root, later], grandchild.ancestors
  end

  def test_subtree_limit_and_order_stay_in_sql
    _, root = create_workspace_root
    later = root.record(RecordingStudioPage) { |page| page.title = "Later" }
    earlier = root.record(RecordingStudioPage) { |page| page.title = "Earlier" }
    grandchild = root.record(RecordingStudioComment, parent_recording: later) { |comment| comment.body = "Nested" }
    ordered_children = [earlier.id, later.id].sort

    relation = root.subtree_recordings

    assert_kind_of ActiveRecord::Relation, relation
    assert_equal [root.id] + ordered_children, relation.limit(3).pluck(:id)
    assert_equal ordered_children, root.subtree_recordings(include_self: false).limit(2).pluck(:id)
    assert_equal ordered_children + [grandchild.id], root.subtree_recordings(include_self: false).limit(4).pluck(:id)
    assert_equal [root.id, ordered_children.first], relation.limit(2).map(&:id)

    sql = capture_sql { root.subtree_recordings(include_self: false).limit(2).pluck(:id) }
    assert(sql.any? { |statement| statement.match?(/ORDER BY id ASC/i) && statement.match?(/\bLIMIT\b/i) })
    refute(sql.any? { |statement| statement.match?(/WITH RECURSIVE/i) })
    refute(sql.any? { |statement| statement.match?(/WHEN '[0-9a-f-]{36}' THEN/i) })
    root_filters = sql.sum { |statement| statement.scan("root_recording_id").size }
    assert_equal 1, root_filters
  end

  def test_recordings_with_descendants_limit_stays_in_sql
    _, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Ancestor" }
    child = root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
    root.record(RecordingStudioComment, parent_recording: child) { |comment| comment.body = "Nested" }
    root.record(RecordingStudioPage) { |page| page.title = "Other" }

    relation = root.recordings_with_descendants(
      type: RecordingStudioPage,
      descendant_type: RecordingStudioComment,
      order: { id: :asc },
      limit: 1
    )

    assert_match(/\bLIMIT\b/i, relation.to_sql)
    assert_match(/WITH RECURSIVE/i, relation.to_sql)
    assert_operator relation.to_sql.bytesize, :<, 20_000
    assert_equal [parent.id, child.id].min, relation.pick(:id)
  end

  def test_recordings_with_descendants_limit_reads_child_owners_by_id
    _, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Ancestor" }
    root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
    leaf = root.record(RecordingStudioPage) { |page| page.title = "Leaf" }

    ids = nil
    sql = capture_sql do
      ids = root.recordings_with_descendants(limit: 10).pluck(:id)
    end
    direct = root.recordings_with_descendants(include_children: false, limit: 10).pluck(:id)

    assert_equal [root.id, parent.id].sort, ids
    assert_not_includes ids, leaf.id
    assert_equal [parent.id], direct
    refute(sql.any? { |statement| statement.match?(/WITH RECURSIVE descendants/i) })
    assert(sql.any? { |statement| statement.match?(/parent_recording_id/i) })
  end

  def test_cycle_raises
    _, root = create_workspace_root
    first = root.record(RecordingStudioPage) { |page| page.title = "First" }
    second = root.record(RecordingStudioPage, parent_recording: first) { |page| page.title = "Second" }
    third = root.record(RecordingStudioPage, parent_recording: second) { |page| page.title = "Third" }
    first.update_columns(parent_recording_id: third.id)

    RecordingStudio::Recording.connection.execute("SET LOCAL statement_timeout = '3s'")

    assert_equal [second.id], first.subtree_recordings(include_self: false).limit(1).pluck(:id)
    assert_includes root.recordings_with_descendants(limit: 1).pluck(:id), [first.id, second.id, third.id].min

    [-> { RecordingStudio::Tree.ancestor_ids(first.id) },
     -> { first.descendant_ids },
     -> { first.subtree_recordings(include_self: false).limit(3).pluck(:id) },
     -> { root.recordings_with_descendants.pluck(:id) }].each do |walk|
      error = assert_raises(RecordingStudio::TreeWalkError, &walk)
      assert_match(/contains a cycle at recording/, error.message)
    end
  end

  def test_depth_cap_allows_1000_and_raises_past_it
    _workspace, root = create_workspace_root
    insert_descendant_chain(root, RecordingStudio::Tree::MAX_WALK_DEPTH)
    leaf = depth_leaf(root)

    assert_equal RecordingStudio::Tree::MAX_WALK_DEPTH, root.descendant_ids.size
    assert_equal RecordingStudio::Tree::MAX_WALK_DEPTH, leaf.ancestors.size
    assert_equal leaf.id, root.subtree_recordings.limit(1).offset(RecordingStudio::Tree::MAX_WALK_DEPTH).pick(:id)

    insert_descendant_chain(leaf, 1)

    assert root.subtree_recordings(include_self: false).limit(1).pick(:id).present?

    [-> { root.descendant_ids },
     -> { depth_leaf(root).ancestors },
     lambda {
       root.subtree_recordings.limit(1).offset(RecordingStudio::Tree::MAX_WALK_DEPTH + 1).pluck(:id)
     }].each do |walk|
      error = assert_raises(RecordingStudio::TreeWalkError, &walk)
      assert_match(/exceeded the depth cap of 1000/, error.message)
    end
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.root_recording_for(workspace)]
  end

  def insert_descendant_chain(parent, length)
    connection = RecordingStudio::Recording.connection
    now = Time.current
    connection.exec_query(<<~SQL.squish)
      WITH RECURSIVE chain AS (
        SELECT gen_random_uuid() AS id,
               #{connection.quote(parent.id)}::uuid AS parent_id,
               1 AS n
        UNION ALL
        SELECT gen_random_uuid(), chain.id, chain.n + 1
        FROM chain
        WHERE chain.n < #{length.to_i}
      )
      INSERT INTO recording_studio_recordings (
        id, parent_recording_id, root_recording_id, recordable_type, recordable_id, created_at, updated_at
      )
      SELECT chain.id,
             chain.parent_id,
             #{connection.quote(parent.root_recording_id || parent.id)}::uuid,
             'Workspace',
             #{connection.quote(parent.recordable_id)}::uuid,
             #{connection.quote(now)},
             #{connection.quote(now)}
      FROM chain
    SQL
  end

  def capture_sql(&)
    queries = []
    callback = lambda { |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless payload[:name] == "SCHEMA"
    }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    queries
  end

  def depth_leaf(root)
    parent_ids = RecordingStudio::Recording.unscoped.where.not(parent_recording_id: nil).select(:parent_recording_id)
    RecordingStudio::Recording.unscoped.where(root_recording_id: root.id).where.not(id: parent_ids).first
  end
end
