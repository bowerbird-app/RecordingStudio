# frozen_string_literal: true

require "test_helper"
require "timeout"

class SingleChildrenTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types.dup
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    @original_rules = RecordingStudio::SingleChildren.snapshot
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
      RecordingStudioCover
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioFolder, RecordingStudioCover)
    RecordingStudioAuthorizedWrites.find_or_create_test_actor
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
    RecordingStudio::SingleChildren.restore!(@original_rules)
    RecordingStudio::DelegatedTypeRegistrar.apply!
    RecordingStudio.unregister_recording_filter(:hide_covers)
  end

  def test_second_cover_under_the_same_parent_is_rejected
    _workspace, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    root.record(RecordingStudioCover, parent_recording: parent) { |cover| cover.title = "First" }

    error = assert_no_difference -> { RecordingStudioCover.count } do
      assert_raises(RecordingStudio::SlotTaken) do
        root.record(RecordingStudioCover, parent_recording: parent) { |cover| cover.title = "Second" }
      end
    end

    assert_equal "RecordingStudioCover already has a recording under this RecordingStudioPage", error.message
    assert_equal 1, covers_under(parent)
  end

  def test_a_hidden_row_still_occupies_the_slot
    _workspace, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    cover = root.record(RecordingStudioCover, parent_recording: parent) { |item| item.title = "Kept out of kept" }
    RecordingStudio.register_recording_filter(
      :hide_covers,
      sql: ->(table) { "#{table}.recordable_type <> 'RecordingStudioCover'" }
    ) { |recordings| recordings.where.not(recordable_type: "RecordingStudioCover") }

    refute_includes RecordingStudio::Recording.kept, cover

    assert_raises(RecordingStudio::SlotTaken) do
      root.record(RecordingStudioCover, parent_recording: parent) { |item| item.title = "Another" }
    end
    assert_equal 1, covers_under(parent)
  end

  def test_revising_the_occupant_replaces_its_recordable
    _workspace, root = create_workspace_root
    cover = root.record(RecordingStudioCover) { |item| item.title = "First" }
    original_recordable_id = cover.recordable_id

    revised = root.revise(cover) { |item| item.title = "Replacement" }

    assert_equal cover.id, revised.id
    refute_equal original_recordable_id, revised.reload.recordable_id
    assert_equal "Replacement", revised.recordable.title
    assert_equal 1, covers_under(root)
  end

  def test_record_events_appends_without_taking_the_slot
    _workspace, root = create_workspace_root
    cover = root.record(RecordingStudioCover) { |item| item.title = "First" }

    events = RecordingStudio.record_events!(
      [{ action: "noted", recording: cover, recordable: cover.recordable }]
    )

    assert_equal ["noted"], events.map(&:action)
    assert_equal cover.id, events.first.recording_id
    assert_equal 1, covers_under(root)
  end

  def test_undeclared_types_can_repeat_under_one_parent
    _workspace, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }

    2.times do |index|
      root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child #{index}" }
    end

    assert_equal 2, RecordingStudioPage.where(title: ["Child 0", "Child 1"]).count
  end

  def test_pairwise_limit_blocks_only_the_named_parent_type
    _workspace, root = create_workspace_root
    folder = root.record(RecordingStudioFolder) { |item| item.name = "Folder" }
    RecordingStudio.declare_single_child(
      "RecordingStudioPage",
      under: "Workspace",
      key: "page-under-workspace"
    )

    root.record(RecordingStudioPage) { |page| page.title = "One workspace page" }
    assert_raises(RecordingStudio::SlotTaken) do
      root.record(RecordingStudioPage) { |page| page.title = "Second workspace page" }
    end
    root.record(RecordingStudioPage, parent_recording: folder) { |page| page.title = "Folder page" }
    root.record(RecordingStudioPage, parent_recording: folder) { |page| page.title = "Another folder page" }

    refute_includes RecordingStudio.single_child_index_types, "RecordingStudioPage"
    assert_includes RecordingStudio.single_child_index_types, "RecordingStudioCover"
    refute RecordingStudio.single_child?("RecordingStudioPage", under: folder)
    assert RecordingStudio.single_child?("RecordingStudioPage", under: root)
  end

  def test_moving_into_an_occupied_slot_raises
    _workspace, root = create_workspace_root
    _other, other_root = create_workspace_root(name: "Other")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Destination" }
    root.record(RecordingStudioCover, parent_recording: parent) { |cover| cover.title = "Stays" }
    moving = other_root.record(RecordingStudioCover) { |cover| cover.title = "Moves" }

    error = assert_raises(RecordingStudio::SlotTaken) do
      RecordingStudio::Recording.transaction do
        RecordingStudio.lock_for_move!(moving, to_parent: parent, to_root: root)
      end
    end

    assert_match(/RecordingStudioCover already has a recording/, error.message)
    assert_equal other_root.id, moving.reload.parent_recording_id
  end

  def test_moving_into_an_empty_slot_and_moving_in_place_are_allowed
    _workspace, root = create_workspace_root
    _other, other_root = create_workspace_root(name: "Other")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Destination" }
    moving = other_root.record(RecordingStudioCover) { |cover| cover.title = "Moves" }

    RecordingStudio::Recording.transaction do
      locks = RecordingStudio.lock_for_move!(moving, to_parent: parent, to_root: root)
      locks[:recording].update!(parent_recording: locks[:to_parent], root_recording_id: root.id)
    end

    assert_equal parent.id, moving.reload.parent_recording_id
    RecordingStudio::Recording.transaction do
      assert RecordingStudio.lock_for_move!(moving, to_parent: parent, to_root: root)
    end
  end

  def test_create_locks_a_single_child_parent_for_update_and_leaves_the_root
    _workspace, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }

    lock_sql = capture_sql do
      root.record(RecordingStudioCover, parent_recording: parent) { |cover| cover.title = "Only" }
    end
    recording_locks = recording_lock_statements(lock_sql)

    assert(recording_locks.any? { |sql| sql.match?(/FOR UPDATE/i) })
    assert(recording_locks.none? { |sql| sql.match?(/FOR SHARE/i) })
    assert_equal 1, covers_under(parent)
  end

  def test_registration_replaces_the_same_key
    first = RecordingStudio.declare_single_child("RecordingStudioPage", under: "Workspace", key: "pages")
    second = RecordingStudio.declare_single_child("RecordingStudioPage", under: %w[Workspace], key: "pages")

    assert_equal "pages", first
    assert_equal first, second
    assert_equal(1, RecordingStudio::SingleChildren.rules.count { |rule| rule.key == "pages" })

    RecordingStudio.declare_single_child("RecordingStudioPage", under: "RecordingStudioFolder", key: "pages")

    refute RecordingStudio.single_child?("RecordingStudioPage", under: "Workspace")
    assert RecordingStudio.single_child?("RecordingStudioPage", under: "RecordingStudioFolder")
    assert RecordingStudio.remove_single_child("pages")
    refute RecordingStudio.remove_single_child("pages")
  end

  def test_registration_survives_reload
    RecordingStudio.declare_single_child("RecordingStudioPage", under: "Workspace", key: "survives-reload")
    registry = RecordingStudio::SingleChildren

    Rails.application.reloader.reload!

    assert_same registry, RecordingStudio::SingleChildren
    assert RecordingStudio.single_child?("RecordingStudioPage", under: "Workspace")
    assert_equal true, RecordingStudio.recordable_declaration_for("RecordingStudioCover").one_per_parent
    assert_equal(1, RecordingStudio::SingleChildren.rules.count { |rule| rule.key == "survives-reload" })
    cover_key = "declaration:RecordingStudioCover"
    assert_equal(1, RecordingStudio::SingleChildren.rules.count { |rule| rule.key == cover_key })
  end

  def test_invalid_one_per_parent_declarations_raise
    error = assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::RecordableDeclarations.register(
        Workspace,
        label: "Workspace",
        plural_label: nil,
        root: true,
        options: { one_per_parent: true }
      )
    end
    assert_match(/one_per_parent requires root: false/, error.message)

    error = assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::RecordableDeclarations.register(
        RecordingStudioPage,
        label: "Page",
        plural_label: nil,
        root: false,
        options: { allowed_parent_types: ["Workspace"], one_per_parent: "yes" }
      )
    end
    assert_match(/one_per_parent must be true or a list of parent types/, error.message)

    error = assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::RecordableDeclarations.register(
        RecordingStudioPage,
        label: "Page",
        plural_label: nil,
        root: false,
        options: { allowed_parent_types: ["Workspace"], one_per_parent: ["RecordingStudioFolder"] }
      )
    end
    assert_match(/not allowed: RecordingStudioFolder/, error.message)
    assert_not RecordingStudio.recordable_declaration_for("Workspace").one_per_parent?
  end

  def test_single_child_index_lists_only_global_configured_types
    RecordingStudio.declare_single_child(
      "RecordingStudioPage",
      under: true,
      key: "every-page"
    )
    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioCover]

    assert_equal ["RecordingStudioCover"], RecordingStudio.single_child_index_types
    assert_equal "recordable_type IN ('RecordingStudioCover')", RecordingStudio::SingleChildren.index_where_sql
    refute_includes RecordingStudio::SingleChildren.index_where_sql, "kept"
    refute_includes RecordingStudio::SingleChildren.index_where_sql, "trashed"
  end

  def test_installed_index_matches_the_cover_declaration
    index = ActiveRecord::Base.connection.indexes(:recording_studio_recordings).find do |candidate|
      candidate.name == RecordingStudio::SingleChildren::INDEX_NAME
    end

    assert index
    assert index.unique
    assert_equal %w[parent_recording_id recordable_type], Array(index.columns)
    assert_includes index.where, "RecordingStudioCover"
    refute_match(/trashed/i, index.where.to_s)
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.create_root_recording!(workspace)]
  end

  def covers_under(parent)
    RecordingStudio::Recording.unscoped.where(
      parent_recording_id: parent.id,
      recordable_type: "RecordingStudioCover"
    ).count
  end

  def capture_sql(&)
    statements = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    statements
  end

  def recording_lock_statements(statements)
    statements.select do |sql|
      sql.match?(/recording_studio_recordings/i) && sql.match?(/FOR (UPDATE|SHARE)/i)
    end
  end
end

class SingleChildConcurrencyTest < ActiveSupport::TestCase
  Session = Struct.new(:thread, :holder)

  class Gate
    def initialize
      @queue = Queue.new
      @opened = false
      @mutex = Mutex.new
    end

    def wait
      @queue.pop
    end

    def open
      @mutex.synchronize do
        return if @opened

        @opened = true
        @queue << true
      end
    end
  end

  self.use_transactional_tests = false

  def setup
    @original_types = RecordingStudio.configuration.recordable_types.dup
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    @original_rules = RecordingStudio::SingleChildren.snapshot
    @threads = []
    @gates = []
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
      RecordingStudioCover
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioCover)
    RecordingStudioAuthorizedWrites.find_or_create_test_actor
  end

  def teardown
    @gates.each(&:open)
    join_threads
    RecordingStudio.configuration.hooks.clear(:after_record)
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
    RecordingStudio::SingleChildren.restore!(@original_rules)
    RecordingStudio::DelegatedTypeRegistrar.apply!
    with_lock_timeout do
      reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioCover)
    end
  end

  def test_concurrent_creates_under_one_parent_yield_one_slot_taken
    _workspace, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Shared" }
    release = track_gate
    paused = Queue.new
    outcomes = Queue.new

    leader = start_session do
      pause_on_first_recording_lock(release, paused) do
        root.record(RecordingStudioCover, parent_recording: parent) { |cover| cover.title = "Leader" }
      end
      outcomes << :created
    rescue RecordingStudio::SlotTaken
      outcomes << :taken
    end
    Timeout.timeout(5) { paused.pop }

    follower = start_session do
      root.record(RecordingStudioCover, parent_recording: parent) { |cover| cover.title = "Follower" }
      outcomes << :created
    rescue RecordingStudio::SlotTaken
      outcomes << :taken
    end
    wait_for_lock_wait
    assert_equal :acquired, try_lock(root.id, "FOR UPDATE NOWAIT")
    assert_equal :blocked, try_lock(parent.id, "FOR UPDATE NOWAIT")
    release.open
    finish_session(leader)
    finish_session(follower)

    assert_equal %i[created taken], [outcomes.pop, outcomes.pop].sort
    assert_equal 1, covers_under(parent)
  end

  def test_create_and_lock_for_move_do_not_deadlock
    _workspace, root = create_workspace_root
    _other, other_root = create_workspace_root(name: "Other")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Destination" }
    moving = other_root.record(RecordingStudioCover) { |cover| cover.title = "Moving" }
    lock_release = track_gate
    paused = Queue.new

    # The parent lock is FOR UPDATE and the root stays unlocked until the insert.
    prober = start_session do
      pause_on_first_recording_lock(lock_release, paused) do
        root.record(RecordingStudioCover, parent_recording: parent) { |cover| cover.title = "Probe" }
      end
    end
    Timeout.timeout(5) { paused.pop }
    assert_equal :acquired, try_lock(root.id, "FOR UPDATE NOWAIT")
    assert_equal :blocked, try_lock(parent.id, "FOR UPDATE NOWAIT")
    lock_release.open
    finish_session(prober)

    open_parent = root.record(RecordingStudioPage) { |page| page.title = "Open" }
    release = track_gate
    held = Queue.new
    RecordingStudio.configuration.hooks.after_record do |event|
      next unless event.recordable.respond_to?(:title) && event.recordable.title == "Created"

      held << true
      release.wait
    end

    creator = start_session do
      root.record(RecordingStudioCover, parent_recording: open_parent) { |cover| cover.title = "Created" }
      :created
    end
    Timeout.timeout(5) { held.pop }

    mover = start_session do
      RecordingStudio::Recording.transaction do
        RecordingStudio.lock_for_move!(moving, to_parent: open_parent, to_root: root)
      end
      :moved
    rescue RecordingStudio::SlotTaken
      :taken
    end
    wait_for_lock_wait
    release.open
    assert_equal :created, finish_session(creator)
    assert_equal :taken, finish_session(mover)
    assert_equal other_root.id, moving.reload.parent_recording_id
    assert_equal 1, covers_under(open_parent)
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.create_root_recording!(workspace)]
  end

  def covers_under(parent)
    RecordingStudio::Recording.unscoped.where(
      parent_recording_id: parent.id,
      recordable_type: "RecordingStudioCover"
    ).count
  end

  def track_gate
    gate = Gate.new
    @gates << gate
    gate
  end

  def pause_on_first_recording_lock(release, paused, &)
    seen = false
    owner = Thread.current
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if seen || Thread.current != owner

      sql = payload[:sql].to_s
      next unless sql.match?(/SELECT/i) && sql.match?(/FOR (UPDATE|SHARE)/i)
      next unless sql.match?(/recording_studio_recordings/i)

      seen = true
      paused << true
      release.wait
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
  end

  def try_lock(id, mode)
    with_session do
      RecordingStudio::Recording.transaction do
        RecordingStudio::Recording.unscoped.lock(mode).find(id)
      end
      :acquired
    rescue ActiveRecord::LockWaitTimeout
      :blocked
    end
  end

  def with_session(&)
    session = start_session(&)
    finish_session(session)
  end

  def start_session
    holder = { error: nil, result: nil }
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        holder[:result] = yield
      end
    rescue StandardError => e
      holder[:error] = e
    end
    @threads << thread
    Session.new(thread, holder)
  end

  def finish_session(session)
    session.thread.join(10)
    raise "database session still running" if session.thread.alive?

    raise session.holder[:error] if session.holder[:error]

    session.holder[:result]
  end

  def join_threads
    @threads.each do |thread|
      next unless thread
      next if thread.join(10)

      cancel_other_queries!
      thread.join(2)
    end
  end

  def cancel_other_queries!
    pids = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
      SELECT pid FROM pg_stat_activity
      WHERE datname = current_database()
        AND pid <> pg_backend_pid()
        AND state <> 'idle'
    SQL
    pids.each do |pid|
      ActiveRecord::Base.connection.select_value("SELECT pg_cancel_backend(#{pid.to_i})")
    end
  end

  def wait_for_lock_wait
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      return if recording_lock_waiters.positive?

      timed_out = Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise "timed out waiting for a row lock" if timed_out

      sleep 0.05
    end
  end

  def recording_lock_waiters
    ActiveRecord::Base.uncached do
      ActiveRecord::Base.connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid <> pg_backend_pid()
          AND wait_event_type = 'Lock'
      SQL
    end
  end

  def with_lock_timeout
    ActiveRecord::Base.connection.execute("SET lock_timeout = '3s'")
    yield
  ensure
    ActiveRecord::Base.connection.execute("SET lock_timeout = 0")
  end
end
