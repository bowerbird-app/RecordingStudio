# frozen_string_literal: true

require "test_helper"

class RootRecordingsTest < ActiveSupport::TestCase
  def setup
    @original_require_actor = RecordingStudio.configuration.require_actor
    @original_allow_unauthorized_writes = RecordingStudio.configuration.allow_unauthorized_writes
    @original_authorize = RecordingStudio.configuration.authorize_write
    @original_actor = RecordingStudio.configuration.actor
    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def teardown
    RecordingStudio.configuration.require_actor = @original_require_actor
    RecordingStudio.configuration.allow_unauthorized_writes = @original_allow_unauthorized_writes
    RecordingStudio.configuration.authorize_write = @original_authorize
    RecordingStudio.configuration.actor = @original_actor
    RecordingStudio.configuration.hooks.clear(:before_record)
    RecordingStudio.configuration.hooks.clear(:after_record)
  end

  def test_root_recording_for_returns_nil_and_does_not_write
    workspace = Workspace.create!(name: "Workspace")

    assert_no_difference -> { RecordingStudio::Recording.count } do
      assert_no_difference -> { RecordingStudio::Event.count } do
        assert_nil RecordingStudio.root_recording_for(workspace)
      end
    end
  end

  def test_root_recording_for_keeps_argument_validation
    assert_raises(ArgumentError) { RecordingStudio.root_recording_for(nil) }
    assert_raises(ArgumentError) { RecordingStudio.root_recording_for(Workspace.new(name: "Draft")) }

    page = RecordingStudioPage.create!(title: "Page")
    assert_no_difference -> { RecordingStudio::Recording.count } do
      assert_raises(RecordingStudio::RootNotAllowed) { RecordingStudio.root_recording_for(page) }
    end
  end

  def test_create_root_recording_requires_an_actor_and_inserts_nothing
    RecordingStudio.configuration.actor = -> {}
    RecordingStudio.configuration.require_actor = true
    workspace = Workspace.create!(name: "Workspace")

    assert_no_difference -> { RecordingStudio::Recording.count } do
      assert_no_difference -> { RecordingStudio::Event.count } do
        assert_raises(RecordingStudio::ActorRequired) do
          RecordingStudio.create_root_recording!(workspace, actor: nil)
        end
      end
    end
    assert_nil RecordingStudio.root_recording_for(workspace)
  end

  def test_create_root_recording_uses_the_configured_actor
    actor = create_actor("configured")
    RecordingStudio.configuration.actor = -> { actor }
    workspace = Workspace.create!(name: "Workspace")

    root = RecordingStudio.create_root_recording!(workspace)

    assert_equal actor, root.events.unscope(:order).first.actor
  end

  def test_create_root_recording_denies_authorization_and_inserts_nothing
    workspace = Workspace.create!(name: "Workspace")
    seen = nil
    RecordingStudio.configuration.authorize_write = lambda { |**context|
      seen = context
      false
    }

    assert_no_difference -> { RecordingStudio::Recording.count } do
      assert_no_difference -> { RecordingStudio::Event.count } do
        error = assert_raises(RecordingStudio::AuthorizationError) do
          RecordingStudio.create_root_recording!(workspace, actor: create_actor("denied"))
        end
        assert_equal "RecordingStudio write was denied by config.authorize_write", error.message
      end
    end

    assert_equal "created", seen[:action]
    assert_equal workspace, seen[:recordable]
    assert_nil seen[:recording]
    assert_nil seen[:root_recording]
    assert_nil seen[:parent_recording]
    assert_nil RecordingStudio.root_recording_for(workspace)
  end

  def test_create_root_recording_runs_hooks_and_writes_one_event
    actor = create_actor("writer")
    workspace = Workspace.create!(name: "Workspace")
    before_payloads = []
    after_events = []
    RecordingStudio.configuration.hooks.before_record { |payload| before_payloads << payload }
    RecordingStudio.configuration.hooks.after_record { |event| after_events << event }

    root = nil
    assert_difference -> { RecordingStudio::Recording.count }, 1 do
      assert_difference -> { RecordingStudio::Event.count }, 1 do
        root = RecordingStudio.create_root_recording!(workspace, actor: actor, metadata: { source: "setup" })
      end
    end

    event = root.events.unscope(:order).first
    assert_equal workspace, root.recordable
    assert_predicate root, :root?
    assert_equal root.id, root.root_recording_id
    assert_equal "created", event.action
    assert_equal actor, event.actor
    assert_equal({ "source" => "setup" }, event.metadata)
    assert_equal root.id, event.root_recording_id
    assert_equal 1, before_payloads.size
    assert_equal "created", before_payloads.first[:action]
    assert_equal workspace, before_payloads.first[:recordable]
    assert_nil before_payloads.first[:recording]
    assert_nil before_payloads.first[:root_recording]
    assert_nil before_payloads.first[:parent_recording]
    assert_equal [event.id], after_events.map(&:id)

    assert_no_difference -> { RecordingStudio::Recording.count } do
      assert_no_difference -> { RecordingStudio::Event.count } do
        assert_equal root, RecordingStudio.create_root_recording!(workspace, actor: actor)
      end
    end
    assert_equal 1, before_payloads.size
    assert_equal 1, after_events.size
  end

  def test_create_root_recording_returns_the_winner_when_the_insert_races
    workspace = Workspace.create!(name: "Race")
    winner = RecordingStudio.create_root_recording!(workspace, actor: create_actor("winner"))
    before_payloads = []
    after_events = []
    RecordingStudio.configuration.hooks.before_record { |payload| before_payloads << payload }
    RecordingStudio.configuration.hooks.after_record { |event| after_events << event }

    found = with_skipped_root_lookup do
      RecordingStudio.create_root_recording!(workspace, actor: create_actor("loser"))
    end

    assert_equal winner, found
    assert_equal 1, RecordingStudio::Recording.unscoped.where(recordable: workspace, parent_recording_id: nil).count
    assert_equal 1, RecordingStudio::Event.where(recording_id: winner.id).count
    assert_equal 1, before_payloads.size
    assert_empty after_events
  end

  private

  def create_actor(name)
    User.create!(
      name: name,
      email: "#{name}-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def with_skipped_root_lookup
    singleton = class << RecordingStudio; self; end
    singleton.alias_method(:__original_find_root_recording, :find_root_recording)
    skipped = false
    singleton.define_method(:find_root_recording) do |recordable|
      if skipped
        __original_find_root_recording(recordable)
      else
        skipped = true
        nil
      end
    end
    yield
  ensure
    singleton = class << RecordingStudio; self; end
    if singleton.method_defined?(:__original_find_root_recording) ||
       singleton.private_method_defined?(:__original_find_root_recording)
      singleton.alias_method(:find_root_recording, :__original_find_root_recording)
      singleton.send(:remove_method, :__original_find_root_recording)
    end
    singleton.send(:private, :find_root_recording)
  end
end

class RootRecordingConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    reset_recording_studio_tables!
  end

  def teardown
    reset_recording_studio_tables!
  end

  def test_concurrent_creates_yield_one_root_and_one_event
    workspace = Workspace.create!(name: "Race")
    actor = User.create!(
      name: "Racer",
      email: "racer-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    ready = Queue.new
    go = Queue.new
    errors = Queue.new

    threads = Array.new(3) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          RecordingStudio.create_root_recording!(workspace, actor: actor)
        end
      rescue StandardError => e
        errors << e
      end
    end

    3.times { ready.pop }
    3.times { go << true }
    threads.each(&:join)

    assert_empty errors
    roots = RecordingStudio::Recording.unscoped.where(recordable: workspace, parent_recording_id: nil)
    assert_equal 1, roots.count
    assert_equal 1, RecordingStudio::Event.where(recording_id: roots.pick(:id)).count
    assert_equal roots.first.id, RecordingStudio::Event.where(recording_id: roots.pick(:id)).pick(:root_recording_id)
  end
end
