# frozen_string_literal: true

require "test_helper"

class RootRecordingIdInvariantTest < ActiveSupport::TestCase
  def setup
    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def test_install_and_upgrade_migrations_match
    root = RecordingStudio::Engine.root
    name = "20261117120000_enforce_recording_studio_recording_root_invariant.rb"
    upgrade = File.read(root.join("db/migrate", name))
    install = File.read(root.join("db/install_migrate", name))

    assert_equal upgrade, install
  end

  def test_root_constraints_are_deferred_and_match_the_parent_chain
    connection = RecordingStudio::Recording.connection
    identity = connection.indexes(:recording_studio_recordings).find do |index|
      index.name == "index_rs_recordings_on_id_and_root"
    end
    check = connection.check_constraints(:recording_studio_recordings).find do |item|
      item.name == "chk_rs_recordings_parentless_own_root"
    end
    foreign_key = connection.foreign_keys(:recording_studio_recordings).find do |item|
      item.name == "fk_rs_recordings_on_parent_and_root"
    end

    assert identity.unique
    assert_equal %w[id root_recording_id], identity.columns.map(&:to_s)
    assert_includes check.expression, "parent_recording_id IS NOT NULL OR root_recording_id = id"
    assert_equal %w[parent_recording_id root_recording_id], Array(foreign_key.column).map(&:to_s)
    assert_equal %w[id root_recording_id], Array(foreign_key.primary_key).map(&:to_s)
    assert_equal :deferred, foreign_key.deferrable
  end

  def test_root_insert_assigns_root_recording_id_before_insert
    workspace = Workspace.create!(name: "Root insert")
    statements = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql].to_s
    end

    root = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      root = RecordingStudio.create_root_recording!(workspace)
    end

    assert_equal root.id, root.root_recording_id
    assert_equal root.id, root.reload.root_recording_id
    assert_predicate root, :root?
    inserts = statements.count { |sql| sql.match?(/INSERT INTO "recording_studio_recordings"/) }
    assert_equal 1, inserts
    assert_empty statements.grep(/UPDATE "recording_studio_recordings"/)
    assert_root_invariant!
  end

  def test_root_insert_keeps_a_client_assigned_id
    chosen = SecureRandom.uuid
    workspace = Workspace.create!(name: "Chosen id")

    root = RecordingStudio::Recording.create!(id: chosen, recordable: workspace, parent_recording_id: nil)

    assert_equal chosen, root.id
    assert_equal chosen, root.reload.root_recording_id
    assert_predicate root, :root?
  end

  def test_child_copies_the_parent_root_on_insert
    root = create_root("Tree")
    child = root.record(RecordingStudioPage) { |page| page.title = "Child" }
    grandchild = root.record(RecordingStudioPage, parent_recording: child) { |page| page.title = "Grand" }

    assert_equal root.id, child.reload.root_recording_id
    assert_equal root.id, grandchild.reload.root_recording_id
    assert_equal child.id, grandchild.parent_recording_id
    assert_root_invariant!
  end

  def test_missing_parent_does_not_make_a_root
    page = RecordingStudioPage.create!(title: "Loose")
    recording = RecordingStudio::Recording.new(recordable: page, parent_recording_id: nil)

    assert_not recording.valid?
    assert_includes recording.errors[:parent_recording_id], "is required for RecordingStudioPage"
    assert_not recording.root?

    recording.save!(validate: false)

    assert recording.parentless?
    assert_equal recording.id, recording.reload.root_recording_id
    assert_not recording.root?
    assert_root_invariant!
  end

  def test_repair_recomputes_root_recording_id_from_the_parent_chain
    migration = root_migration
    root = create_root("Repaired")
    other = create_root("Other")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
    drop_root_constraints!

    root.update_columns(root_recording_id: other.id)
    parent.update_columns(root_recording_id: other.id)
    child.update_columns(root_recording_id: nil)
    error = assert_raises(Minitest::Assertion) { assert_root_invariant! }
    assert_match(/root_recording_id invariant failed/, error.message)

    migration.send(:repair_root_recording_ids)

    assert_equal root.id, root.reload.root_recording_id
    assert_equal root.id, parent.reload.root_recording_id
    assert_equal root.id, child.reload.root_recording_id
    assert_root_invariant!
  end

  def test_repair_stops_on_a_cycle_with_no_parentless_recording
    migration = root_migration
    drop_root_constraints!
    now = Time.current
    first_id = SecureRandom.uuid
    second_id = SecureRandom.uuid
    RecordingStudio::Recording.insert_all(
      [first_id, second_id].map do |id|
        {
          id: id,
          recordable_type: "RecordingStudioPage",
          recordable_id: RecordingStudioPage.create!(title: id).id,
          parent_recording_id: nil,
          root_recording_id: nil,
          created_at: now,
          updated_at: now
        }
      end
    )
    RecordingStudio::Recording.where(id: first_id).update_all(parent_recording_id: second_id)
    RecordingStudio::Recording.where(id: second_id).update_all(parent_recording_id: first_id)

    migration.send(:repair_root_recording_ids)

    error = assert_raises(RuntimeError) { migration.send(:assert_roots_repaired!) }
    assert_match(/cannot be repaired/, error.message)
    assert_nil RecordingStudio::Recording.find(first_id).root_recording_id
  end

  private

  def create_root(name)
    RecordingStudio.create_root_recording!(Workspace.create!(name: name))
  end

  def root_migration
    unless defined?(EnforceRecordingStudioRecordingRootInvariant)
      load RecordingStudio::Engine.root.join(
        "db/install_migrate/20261117120000_enforce_recording_studio_recording_root_invariant.rb"
      ).to_s
    end
    migration = EnforceRecordingStudioRecordingRootInvariant.new
    migration.verbose = false
    migration
  end

  def drop_root_constraints!
    connection = RecordingStudio::Recording.connection
    connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    connection.remove_check_constraint :recording_studio_recordings, name: "chk_rs_recordings_parentless_own_root"
    connection.remove_foreign_key :recording_studio_recordings, name: "fk_rs_recordings_on_parent_and_root"
    connection.change_column_null :recording_studio_recordings, :root_recording_id, true
  end
end

class RootRecordingIdConstraintTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def teardown
    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def test_cross_root_subtree_move_commits_when_descendants_are_updated
    _source, destination, parent, child, grandchild = build_subtree
    child.log_event!(action: "noted")

    RecordingStudio::Recording.transaction do
      locks = RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: destination)
      assert_equal [child.id, grandchild.id].map(&:to_s).sort, locks[:descendant_ids].map(&:to_s).sort
      if locks[:descendant_ids].any?
        RecordingStudio::Recording.where(id: locks[:descendant_ids]).update_all(root_recording_id: destination.id)
      end
      locks[:recording].update!(parent_recording: locks[:to_parent], root_recording_id: destination.id)
    end

    [parent, child, grandchild].each do |recording|
      assert_equal destination.id, recording.reload.root_recording_id
    end
    assert_equal destination.id, parent.reload.parent_recording_id
    assert_equal destination.id, child.events.pick(:root_recording_id)
    assert_root_invariant!
  end

  def test_cross_root_move_that_forgets_descendants_fails_at_commit
    source, destination, parent, child, grandchild = build_subtree

    error = assert_raises(ActiveRecord::InvalidForeignKey) do
      RecordingStudio::Recording.transaction do
        locks = RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: destination)
        locks[:recording].update!(parent_recording: locks[:to_parent], root_recording_id: destination.id)
        assert_equal destination.id, locks[:recording].reload.root_recording_id
        assert_equal source.id, child.reload.root_recording_id
      end
    end

    assert_match(/fk_rs_recordings_on_parent_and_root/, error.message)
    assert_equal source.id, parent.reload.root_recording_id
    assert_equal source.id, parent.parent_recording_id
    assert_equal source.id, child.reload.root_recording_id
    assert_equal source.id, grandchild.reload.root_recording_id
    assert_root_invariant!
  end

  def test_database_rejects_a_child_root_changed_with_update_columns
    _source, other, _parent, child, _grandchild = build_subtree
    original = child.root_recording_id

    error = assert_commit_failure do
      child.update_columns(root_recording_id: other.id)
      assert_equal other.id, child.reload.root_recording_id
    end

    assert_match(/fk_rs_recordings_on_parent_and_root/, error.message)
    assert_equal original, child.reload.root_recording_id
  end

  def test_database_rejects_a_child_root_changed_with_update_all
    _source, other, _parent, child, _grandchild = build_subtree
    original = child.root_recording_id

    error = assert_commit_failure do
      RecordingStudio::Recording.where(id: child.id).update_all(root_recording_id: other.id)
      assert_equal other.id, child.reload.root_recording_id
    end

    assert_match(/fk_rs_recordings_on_parent_and_root/, error.message)
    assert_equal original, child.reload.root_recording_id
  end

  def test_database_rejects_a_child_root_inserted_with_insert_all
    _source, other, parent, _child, _grandchild = build_subtree
    new_id = SecureRandom.uuid

    error = assert_commit_failure do
      row = recording_row(new_id, parent_recording_id: parent.id, root_recording_id: other.id)
      RecordingStudio::Recording.insert_all([row])
      assert RecordingStudio::Recording.exists?(new_id)
    end

    assert_match(/fk_rs_recordings_on_parent_and_root/, error.message)
    assert_not RecordingStudio::Recording.exists?(new_id)
  end

  def test_database_rejects_a_child_root_changed_with_sql
    _source, other, _parent, child, _grandchild = build_subtree
    original = child.root_recording_id
    connection = RecordingStudio::Recording.connection

    error = assert_commit_failure do
      connection.execute(<<~SQL.squish)
        UPDATE recording_studio_recordings
        SET root_recording_id = #{connection.quote(other.id)}
        WHERE id = #{connection.quote(child.id)}
      SQL
      assert_equal other.id, child.reload.root_recording_id
    end

    assert_match(/fk_rs_recordings_on_parent_and_root/, error.message)
    assert_equal original, child.reload.root_recording_id
  end

  def test_database_rejects_a_parentless_row_whose_root_is_not_its_id
    root = create_root("Only")
    other = create_root("Other")

    error = assert_raises(ActiveRecord::CheckViolation) do
      root.update_columns(root_recording_id: other.id)
    end
    assert_match(/chk_rs_recordings_parentless_own_root/, error.message)
    assert_equal root.id, root.reload.root_recording_id

    new_id = SecureRandom.uuid
    assert_raises(ActiveRecord::CheckViolation) do
      RecordingStudio::Recording.insert_all(
        [recording_row(new_id, parent_recording_id: nil, root_recording_id: other.id)]
      )
    end
    assert_not RecordingStudio::Recording.exists?(new_id)

    connection = RecordingStudio::Recording.connection
    assert_raises(ActiveRecord::CheckViolation) do
      connection.execute(<<~SQL.squish)
        UPDATE recording_studio_recordings
        SET root_recording_id = #{connection.quote(other.id)}
        WHERE id = #{connection.quote(root.id)}
      SQL
    end
    assert_equal root.id, root.reload.root_recording_id
  end

  def test_database_rejects_a_null_root
    root = create_root("Only")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }

    [root, parent].each do |recording|
      error = assert_raises(ActiveRecord::NotNullViolation) do
        recording.update_columns(root_recording_id: nil)
      end
      assert_match(/root_recording_id/, error.message)
      assert_equal root.id, recording.reload.root_recording_id
    end
  end

  private

  def create_root(name)
    RecordingStudio.create_root_recording!(Workspace.create!(name: "#{name} #{SecureRandom.hex(4)}"))
  end

  def build_subtree
    source = create_root("Source")
    destination = create_root("Destination")
    parent = source.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = source.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
    grandchild = source.record(RecordingStudioPage, parent_recording: child) { |page| page.title = "Grand" }
    [source, destination, parent, child, grandchild]
  end

  def recording_row(id, parent_recording_id:, root_recording_id:)
    now = Time.current
    {
      id: id,
      recordable_type: "RecordingStudioPage",
      recordable_id: RecordingStudioPage.create!(title: id).id,
      parent_recording_id: parent_recording_id,
      root_recording_id: root_recording_id,
      created_at: now,
      updated_at: now
    }
  end

  def assert_commit_failure(&)
    assert_raises(ActiveRecord::InvalidForeignKey) do
      RecordingStudio::Recording.transaction(&)
    end
  end
end
