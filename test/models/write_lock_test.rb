# frozen_string_literal: true

require "test_helper"
require "timeout"

class WriteLockGate
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

class WriteLockTest < ActiveSupport::TestCase
  Session = Struct.new(:thread, :holder)

  self.use_transactional_tests = false

  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    @threads = []
    @gates = []

    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioComment, RecordingStudioFolder)
    RecordingStudioAuthorizedWrites.find_or_create_test_actor
  end

  def teardown
    @gates.each(&:open)
    join_threads
    RecordingStudio.configuration.hooks.clear(:after_record)
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
    with_lock_timeout do
      reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioComment, RecordingStudioFolder)
    end
  end

  def test_update_and_create_under_the_same_recording_do_not_deadlock
    _, root = create_workspace_root
    page = root.record(RecordingStudioPage) { |item| item.title = "X" }

    run_locked_pair(root, page, first: :update)
    run_locked_pair(root, page, first: :create)

    assert_operator RecordingStudioPage.where(title: "Child of X").count, :>=, 2
  end

  def test_creates_in_different_branches_do_not_block_each_other
    _, root = create_workspace_root
    branch_a = root.record(RecordingStudioPage) { |page| page.title = "Branch A" }
    branch_b = root.record(RecordingStudioPage) { |page| page.title = "Branch B" }
    release = track_gate
    held = Queue.new
    hold_after_record("Under A", held, release)

    first = start_session do
      root.record(RecordingStudioPage, parent_recording: branch_a) { |page| page.title = "Under A" }
    end
    Timeout.timeout(5) { held.pop }

    second_done = Queue.new
    second = start_session do
      root.record(RecordingStudioPage, parent_recording: branch_b) { |page| page.title = "Under B" }
      second_done << true
    end
    Timeout.timeout(5) { second_done.pop }
    release.open
    finish_session(first)
    finish_session(second)
    assert RecordingStudioPage.exists?(title: "Under A")
    assert RecordingStudioPage.exists?(title: "Under B")
  end

  def test_creates_under_one_parent_do_not_block_each_other
    _, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Shared parent" }
    release = track_gate
    held = Queue.new
    hold_after_record("First share", held, release)

    first = start_session do
      root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "First share" }
    end
    Timeout.timeout(5) { held.pop }

    second_done = Queue.new
    second = start_session do
      root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Second share" }
      second_done << true
    end
    Timeout.timeout(5) { second_done.pop }
    release.open
    finish_session(first)
    finish_session(second)
    assert RecordingStudioPage.exists?(title: "First share")
    assert RecordingStudioPage.exists?(title: "Second share")
  end

  def test_create_locks_the_parent_for_share_and_not_the_root
    _, root = create_workspace_root
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    release = track_gate
    paused = Queue.new

    creator = start_session do
      pause_on_first_recording_lock(release, paused) do
        root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
      end
    end
    Timeout.timeout(5) { paused.pop }

    assert_equal :blocked, try_lock(parent.id, "FOR UPDATE NOWAIT")
    assert_equal :acquired, try_lock(parent.id, "FOR SHARE NOWAIT")
    assert_equal :acquired, try_lock(root.id, "FOR UPDATE NOWAIT")
    release.open
    finish_session(creator)

    lock_sql = capture_sql do
      root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Another child" }
    end
    recording_locks = recording_lock_statements(lock_sql)
    assert(recording_locks.any? { |sql| sql.match?(/FOR SHARE/i) })
    assert(recording_locks.none? { |sql| sql.match?(/FOR UPDATE/i) })
  end

  def test_update_locks_the_recording_and_not_the_root
    _, root = create_workspace_root
    page = root.record(RecordingStudioPage) { |item| item.title = "Before" }
    release = track_gate
    paused = Queue.new

    updater = start_session do
      pause_on_first_recording_lock(release, paused) do
        root.revise(page) { |item| item.title = "After" }
      end
    end
    Timeout.timeout(5) { paused.pop }

    assert_equal :blocked, try_lock(page.id, "FOR UPDATE NOWAIT")
    assert_equal :acquired, try_lock(root.id, "FOR UPDATE NOWAIT")
    release.open
    finish_session(updater)
    assert_equal "After", page.reload.recordable.title

    lock_sql = capture_sql { root.revise(page) { |item| item.title = "After again" } }
    recording_locks = recording_lock_statements(lock_sql)
    assert(recording_locks.any? { |sql| sql.match?(/FOR UPDATE/i) })
    assert(recording_locks.none? { |sql| sql.match?(/FOR SHARE/i) })
  end

  def test_lock_for_move_requires_a_transaction_and_a_matching_root
    root, destination, parent, _child, _sibling = build_tree

    error = assert_raises(ArgumentError) do
      RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: destination)
    end
    assert_includes error.message, "inside a transaction"

    error = assert_raises(ArgumentError) do
      RecordingStudio::Recording.transaction do
        RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: root)
      end
    end
    assert_includes error.message, "to_parent must belong to to_root"
  end

  def test_lock_for_move_locks_roots_before_the_recording
    root, destination, parent, _child, _sibling = build_tree
    higher = [root, destination].max_by { |recording| recording.id.to_s }
    release = track_gate
    holding = Queue.new

    blocker = start_session do
      RecordingStudio::Recording.transaction do
        RecordingStudio::Recording.unscoped.lock.find(higher.id)
        holding << true
        release.wait
      end
    end
    Timeout.timeout(5) { holding.pop }

    mover = start_session do
      RecordingStudio::Recording.transaction do
        RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: destination)
      end
    end
    wait_for_lock_wait
    assert_equal :acquired, try_lock(parent.id, "FOR UPDATE NOWAIT")
    release.open
    finish_session(blocker)
    finish_session(mover)
  end

  def test_lock_for_move_locks_the_subtree_and_not_a_sibling
    root, destination, parent, child, sibling = build_tree
    locks = nil

    RecordingStudio::Recording.transaction do
      locks = RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: destination)
      assert_equal [child.id.to_s], locks[:descendant_ids].map(&:to_s)
      assert_predicate locks, :frozen?
      assert_equal :blocked, try_lock(root.id, "FOR UPDATE NOWAIT")
      assert_equal :blocked, try_lock(destination.id, "FOR UPDATE NOWAIT")
      assert_equal :blocked, try_lock(parent.id, "FOR UPDATE NOWAIT")
      assert_equal :blocked, try_lock(child.id, "FOR UPDATE NOWAIT")
      assert_equal :acquired, try_lock(sibling.id, "FOR UPDATE NOWAIT")
    end

    assert_equal :acquired, try_lock(parent.id, "FOR UPDATE NOWAIT")
  end

  def test_move_and_a_create_under_the_subtree_share_one_root
    root, destination, parent, child, sibling = build_tree
    parent.log_event!(action: "parent-note")
    child.log_event!(action: "child-note")
    release = track_gate
    held = Queue.new
    hold_after_record("During move", held, release)

    creator = start_session do
      root.record(RecordingStudioPage, parent_recording: child) { |page| page.title = "During move" }
    end
    new_id = Timeout.timeout(5) { held.pop }

    mover = start_session { move_recording!(parent, destination) }
    wait_for_lock_wait
    release.open
    finish_session(mover)
    finish_session(creator)

    new_recording = RecordingStudio::Recording.unscoped.find(new_id)
    [parent, child, new_recording].each do |recording|
      assert_equal destination.id, recording.reload.root_recording_id
      events = RecordingStudio::Event.unscoped.where(recording_id: recording.id)
      assert events.any?
      events.each do |event|
        assert_equal destination.id, event.root_recording_id
      end
    end
    assert_equal root.id, sibling.reload.root_recording_id
    assert_equal root.id, sibling.events.first.root_recording_id
    assert_roots_match_parents
  end

  def test_create_waits_for_a_move_and_does_not_write_a_stale_root
    root, destination, parent, child, _sibling = build_tree
    release = track_gate
    holding = Queue.new

    mover = start_session do
      RecordingStudio::Recording.transaction do
        locks = RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: destination)
        if locks[:descendant_ids].any?
          RecordingStudio::Recording.where(id: locks[:descendant_ids]).update_all(root_recording_id: destination.id)
        end
        locks[:recording].update!(parent_recording: locks[:to_parent], root_recording_id: destination.id)
        holding << true
        release.wait
      end
    end
    Timeout.timeout(5) { holding.pop }

    creator = start_session do
      root.record(RecordingStudioPage, parent_recording: child) { |page| page.title = "Late" }
    end
    wait_for_lock_wait
    assert_nil RecordingStudioPage.find_by(title: "Late")
    release.open
    finish_session(mover)
    creator.thread.join(10)
    assert_kind_of ArgumentError, creator.holder[:error]
    assert_includes creator.holder[:error].message, "parent_recording must belong to the provided root_recording"
    assert_nil RecordingStudioPage.find_by(title: "Late")

    fresh_child = RecordingStudio::Recording.unscoped.find(child.id)
    created = destination.record(RecordingStudioPage, parent_recording: fresh_child) { |page| page.title = "After" }
    assert_equal destination.id, created.root_recording_id
    assert_equal destination.id, created.events.pick(:root_recording_id)
    assert_roots_match_parents
  end

  def test_hooks_run_before_the_write_commits
    _, root = create_workspace_root
    visible = nil
    RecordingStudio.configuration.hooks.after_record do |event|
      visible = with_session do
        RecordingStudio::Event.unscoped.where(id: event.id).exists?
      end
    end

    root.record(RecordingStudioPage) { |page| page.title = "Inside" }

    assert_equal false, visible
    assert RecordingStudioPage.exists?(title: "Inside")
  end

  def test_move_conflict_rejects_an_id_that_sorts_before_a_held_lock
    error = assert_raises(RecordingStudio::MoveConflict) do
      move_lock.send(:assert_lock_order!, ["a"], ["m"])
    end
    assert_includes error.message, "Retry the move"
    move_lock.send(:assert_lock_order!, ["m"], ["a"])
    move_lock.send(:assert_lock_order!, ["m"], [])
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.root_recording_for(workspace)]
  end

  def build_tree
    _, root = create_workspace_root(name: "From #{SecureRandom.hex(4)}")
    _, destination = create_workspace_root(name: "To #{SecureRandom.hex(4)}")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
    sibling = root.record(RecordingStudioPage) { |page| page.title = "Sibling" }
    [root, destination, parent, child, sibling]
  end

  def move_lock
    RecordingStudio::Locks::Move.new(nil, nil, nil)
  end

  def move_recording!(recording, destination)
    attempts = 0
    begin
      attempts += 1
      RecordingStudio::Recording.transaction do
        locks = RecordingStudio.lock_for_move!(recording, to_parent: destination, to_root: destination)
        if locks[:descendant_ids].any?
          RecordingStudio::Recording.where(id: locks[:descendant_ids]).update_all(root_recording_id: destination.id)
        end
        locks[:recording].update!(parent_recording: locks[:to_parent], root_recording_id: destination.id)
      end
    rescue RecordingStudio::MoveConflict
      retry if attempts < 5
      raise
    end
  end

  def run_locked_pair(root, page, first:)
    release = track_gate
    paused = Queue.new
    leader_call = first == :update ? -> { revise_page(root, page) } : -> { create_under(root, page) }
    follower_call = first == :update ? -> { create_under(root, page) } : -> { revise_page(root, page) }

    leader = start_session do
      pause_on_first_recording_lock(release, paused) { leader_call.call }
    end
    Timeout.timeout(5) { paused.pop }
    follower = start_session { follower_call.call }
    wait_for_lock_wait
    release.open
    finish_session(leader)
    finish_session(follower)
  end

  def revise_page(root, page)
    root.revise(page) { |item| item.title = "Revised #{SecureRandom.hex(2)}" }
  end

  def create_under(root, page)
    root.record(RecordingStudioPage, parent_recording: page) { |item| item.title = "Child of X" }
  end

  def hold_after_record(title, held, release)
    RecordingStudio.configuration.hooks.after_record do |event|
      next unless event.recordable.respond_to?(:title) && event.recordable.title == title

      held << event.recording_id
      release.wait
    end
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

  def track_gate
    gate = WriteLockGate.new
    @gates << gate
    gate
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

  # The test connection caches identical selects. This count has to see a
  # waiter that appears after the first check.
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

  def with_lock_timeout
    ActiveRecord::Base.connection.execute("SET lock_timeout = '3s'")
    yield
  ensure
    ActiveRecord::Base.connection.execute("SET lock_timeout = 0")
  end

  def assert_roots_match_parents
    RecordingStudio::Recording.unscoped.where.not(parent_recording_id: nil).find_each do |recording|
      parent_root_id = RecordingStudio::Recording.unscoped.where(id: recording.parent_recording_id)
                                                 .pick(:root_recording_id)
      parent_root_id = parent_root_id.presence || recording.parent_recording_id
      assert_equal parent_root_id, recording.root_recording_id
      RecordingStudio::Event.unscoped.where(recording_id: recording.id).find_each do |event|
        assert_equal recording.root_recording_id, event.root_recording_id
      end
    end
  end
end
