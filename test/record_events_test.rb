# frozen_string_literal: true

require "test_helper"

class RecordEventsTest < ActiveSupport::TestCase
  COMPARED_EVENT_ATTRIBUTES = %w[
    action
    recordable_type
    previous_recordable_type
    actor_type
    actor_id
    impersonator_type
    impersonator_id
    idempotency_key
    root_recording_id
  ].freeze

  def setup
    @original_actor = RecordingStudio.configuration.actor
    @original_impersonator = RecordingStudio.configuration.impersonator
    @original_authorizer = RecordingStudio.configuration.authorize_write
    @original_notifications = RecordingStudio.configuration.event_notifications_enabled

    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio.configuration.event_notifications_enabled = true
    RecordingStudio::DelegatedTypeRegistrar.apply!
    clear_record_hooks!
    reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioComment)
  end

  def teardown
    clear_record_hooks!
    RecordingStudio.configuration.actor = @original_actor
    RecordingStudio.configuration.impersonator = @original_impersonator
    RecordingStudio.configuration.authorize_write = @original_authorizer
    RecordingStudio.configuration.event_notifications_enabled = @original_notifications
  end

  def test_record_events_matches_record_for_attributes_hooks_notifications_and_counters
    observed = observe_matching_writes
    assert_equal observed.fetch(:single_events), observed.fetch(:batch_events)
    assert_equal phase(observed.fetch(:single_trace), :before), phase(observed.fetch(:batch_trace), :before)
    assert_equal phase(observed.fetch(:single_trace), :after), phase(observed.fetch(:batch_trace), :after)
    assert_equal observed.fetch(:single_notifications), observed.fetch(:batch_notifications)
    assert_equal %i[before before before instrument after instrument after instrument after],
                 observed.fetch(:batch_trace).map(&:first)
    assert_equal %i[before instrument after], observed.fetch(:single_trace).map(&:first).first(3)
    assert_equal observed.fetch(:single_count), observed.fetch(:batch_count)
  end

  def test_record_events_rolls_back_the_whole_batch_when_one_row_is_invalid
    _workspace, root = create_workspace_root
    page = create_page(root, "Kept")
    other = create_page(root, "Other")
    actor = create_user("Actor", "actor@example.com")
    before_events = RecordingStudio::Event.count
    before_recordings = RecordingStudio::Recording.count
    recordable_id = page.recordable_id

    error = assert_raises(ArgumentError) do
      RecordingStudio.record_events!([
                                       log_entry(page, actor, "reviewed"),
                                       log_entry(page, actor, "published").merge(recordable: other.recordable)
                                     ])
    end

    assert_equal "recordable must match the recording", error.message
    assert_equal before_events, RecordingStudio::Event.count
    assert_equal before_recordings, RecordingStudio::Recording.count
    assert_equal recordable_id, page.reload.recordable_id
    assert_equal 1, page.recordable.reload.events_count
  end

  def test_record_events_rejects_an_invalid_event_before_insert
    _workspace, root = create_workspace_root
    page = create_page(root, "Kept")
    actor = create_user("Actor", "actor@example.com")
    before_events = RecordingStudio::Event.count

    assert_raises(ActiveRecord::RecordInvalid) do
      RecordingStudio.record_events!([
                                       log_entry(page, actor, "reviewed"),
                                       log_entry(page, actor, nil)
                                     ])
    end

    assert_equal before_events, RecordingStudio::Event.count
    assert_equal 1, page.recordable.reload.events_count
  end

  def test_authorization_denial_rejects_the_whole_batch
    _workspace, root = create_workspace_root
    page = create_page(root, "Kept")
    actor = create_user("Actor", "actor@example.com")
    seen = []
    befores = []
    RecordingStudio.configuration.hooks.before_record { |payload| befores << payload[:action] }
    RecordingStudio.configuration.authorize_write = lambda do |action:, **|
      seen << action
      action != "denied"
    end
    before_events = RecordingStudio::Event.count

    assert_raises(RecordingStudio::AuthorizationError) do
      RecordingStudio.record_events!([
                                       log_entry(page, actor, "reviewed"),
                                       log_entry(page, actor, "denied")
                                     ])
    end

    assert_equal %w[reviewed denied], seen
    assert_empty befores
    assert_equal before_events, RecordingStudio::Event.count
    assert_equal 1, page.recordable.reload.events_count
  end

  def test_record_events_query_count_stays_constant_as_the_batch_grows
    _workspace, root = create_workspace_root
    pages = [create_page(root, "One"), create_page(root, "Two")]
    actor = create_user("Actor", "actor@example.com")
    RecordingStudio.record_events!([log_entry(pages.first, actor, "warmup")])

    small = statements_for(batch_for(pages, actor, 10))
    large = statements_for(batch_for(pages, actor, 400))

    message = "10=#{small.size} 400=#{large.size}\n10:\n#{small.join("\n")}\n400:\n#{large.join("\n")}"
    assert_equal small.size, large.size, message
    assert_equal(1, small.count { |sql| sql.match?(/INSERT INTO "recording_studio_events"/) })
    assert_equal(1, large.count { |sql| sql.match?(/INSERT INTO "recording_studio_events"/) })
    assert_equal(1, small.count { |sql| sql.match?(/FOR UPDATE/) })
    assert_equal(1, large.count { |sql| sql.match?(/FOR UPDATE/) })
    assert_operator small.size, :<, 20
    puts "QUERY_COUNTS 10=#{small.size} 400=#{large.size}"
  end

  def test_record_events_joins_the_caller_transaction
    _workspace, root = create_workspace_root
    page = create_page(root, "Outer")
    actor = create_user("Actor", "actor@example.com")
    single = create_page(root, "Single outer")
    seen_during_batch = nil
    seen_during_single = nil

    RecordingStudio::Recording.transaction do
      RecordingStudio.record_events!([log_entry(page, actor, "reviewed"), log_entry(page, actor, "published")])
      assert_equal 2, page.events.where(action: %w[reviewed published]).count
      seen_during_batch = page.recordable.reload.events_count
    end

    RecordingStudio::Recording.transaction do
      RecordingStudio.record!(**record_kwargs(log_entry(single, actor, "reviewed"), single))
      seen_during_single = single.recordable.reload.events_count
    end

    assert_equal seen_during_single, seen_during_batch
    assert_equal 1, seen_during_batch
    assert_equal 3, page.recordable.reload.events_count
    assert_equal 2, single.recordable.reload.events_count

    rolled_back = create_page(root, "Rollback")
    before_events = RecordingStudio::Event.count
    assert_raises(RuntimeError) do
      RecordingStudio::Recording.transaction do
        RecordingStudio.record_events!([log_entry(rolled_back, actor, "reviewed")])
        raise "rollback the batch"
      end
    end

    assert_equal before_events, RecordingStudio::Event.count
    assert_equal 1, rolled_back.recordable.reload.events_count
  end

  def test_record_events_honors_occurred_at_and_orders_defaults
    _workspace, root = create_workspace_root
    page = create_page(root, "Times")
    actor = create_user("Actor", "actor@example.com")
    explicit = Time.zone.parse("2024-01-02 03:04:05 UTC")
    events = RecordingStudio.record_events!([
                                              log_entry(page, actor, "first"),
                                              log_entry(page, actor, "second").merge(occurred_at: explicit),
                                              log_entry(page, actor, "third")
                                            ])

    assert_equal %w[first second third], events.map(&:action)
    assert_equal explicit, events[1].occurred_at
    assert_operator events[0].occurred_at, :<, events[2].occurred_at
    logged = RecordingStudio::Event.where(id: events.map(&:id)).order(occurred_at: :asc, id: :asc)
    assert_equal %w[second first third], logged.map(&:action)
  end

  def test_record_events_locks_targets_without_a_root_update_lock
    _workspace, root = create_workspace_root
    later = create_page(root, "Later")
    earlier = create_page(root, "Earlier")
    actor = create_user("Actor", "actor@example.com")
    ordered = [later, earlier].sort_by { |recording| recording.id.to_s }
    rows = statement_rows([log_entry(ordered.last, actor, "second"), log_entry(ordered.first, actor, "first")])
    assert_target_lock(rows, ordered, root)
  end

  def test_record_events_rejects_idempotency_keys_and_bad_entries
    _workspace, root = create_workspace_root
    page = create_page(root, "Keys")
    actor = create_user("Actor", "actor@example.com")

    assert_raises(ArgumentError) { RecordingStudio.record_events!(nil) }
    assert_equal [], RecordingStudio.record_events!([])
    assert_raises(ArgumentError) do
      RecordingStudio.record_events!([log_entry(page, actor, "reviewed").merge(idempotency_key: "retry")])
    end
    assert_raises(ArgumentError) do
      RecordingStudio.record_events!([log_entry(page, actor, "reviewed").merge(idempotency_key: nil)])
    end
    assert_equal 1, RecordingStudio::Event.where(recording_id: page.id).count
  end

  private

  def observe_matching_writes
    _workspace, root = create_workspace_root
    actor = create_user("Actor", "actor@example.com")
    impersonator = create_user("Impersonator", "impersonator@example.com")
    fallback = create_user("Fallback", "fallback@example.com")
    RecordingStudio.configuration.actor = -> { actor }
    RecordingStudio.configuration.impersonator = -> { fallback }
    single_page = create_page(root, "Single")
    batch_page = create_page(root, "Batch")
    specs = entry_specs(actor, impersonator, parity_times)
    single = capture_single(specs, single_page)
    batch = capture_batch(specs, batch_page)
    single.merge(batch).merge(counts_for(single_page, batch_page))
  end

  def parity_times
    [Time.current - 3.hours, Time.current - 2.hours, Time.current - 1.hour]
  end

  def capture_single(specs, recording)
    trace = []
    notifications = []
    events = with_observers(trace, notifications) { specs.map { |spec| record_one(spec, recording) } }
    { single_trace: trace, single_notifications: notifications, single_events: events.map do |event|
      comparable_event(event)
    end }
  end

  def capture_batch(specs, recording)
    trace = []
    notifications = []
    events = with_observers(trace, notifications) do
      RecordingStudio.record_events!(specs.map do |spec|
        batch_entry(spec, recording)
      end)
    end
    { batch_trace: trace, batch_notifications: notifications, batch_events: events.map do |event|
      comparable_event(event)
    end }
  end

  def record_one(spec, recording)
    RecordingStudio.record!(**record_kwargs(spec, recording))
  end

  def counts_for(single_page, batch_page)
    {
      single_count: single_page.recordable.reload.events_count,
      batch_count: batch_page.recordable.reload.events_count
    }
  end

  def phase(trace, kind)
    trace.select { |entry_kind, _payload| entry_kind == kind }.map(&:last)
  end

  def entry_specs(actor, impersonator, times)
    [
      { action: "reviewed", actor: actor, impersonator: impersonator, metadata: { source: "desk" },
        occurred_at: times[0] },
      { action: "published", actor: actor, impersonator: nil, metadata: {}, occurred_at: times[1] },
      { action: "archived", actor: nil, impersonator: impersonator, metadata: { "note" => "done" },
        occurred_at: times[2] }
    ]
  end

  def record_kwargs(spec, recording)
    {
      action: spec.fetch(:action),
      recordable: recording.recordable,
      recording: recording,
      actor: spec[:actor],
      impersonator: spec[:impersonator],
      metadata: spec.fetch(:metadata, {}),
      occurred_at: spec[:occurred_at]
    }
  end

  def batch_entry(spec, recording)
    record_kwargs(spec, recording).except(:occurred_at).merge(occurred_at: spec[:occurred_at])
  end

  def log_entry(recording, actor, action)
    {
      action: action,
      recording: recording,
      recordable: recording.recordable,
      actor: actor,
      metadata: { source: "batch" }
    }
  end

  def batch_for(pages, actor, count)
    count.times.map { |index| log_entry(pages[index % pages.length], actor, "tick-#{index}") }
  end

  def comparable_event(event)
    compared = COMPARED_EVENT_ATTRIBUTES.index_with { |name| event.public_send(name) }
    assert_equal event.recordable_id, event.previous_recordable_id
    assert_equal event.recording.recordable_id, event.recordable_id
    compared.merge(
      "metadata" => event.metadata.deep_stringify_keys,
      "occurred_at" => event.occurred_at.iso8601(6),
      "recordable_id" => :page,
      "previous_recordable_id" => :page,
      "recording_id" => :recording
    )
  end

  def with_observers(trace, notifications)
    RecordingStudio.configuration.hooks.before_record do |payload|
      trace << [:before, hook_signature(payload)]
    end
    RecordingStudio.configuration.hooks.after_record do |event|
      trace << [:after, after_signature(event)]
    end
    subscriber = ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
      payload = ActiveSupport::Notifications::Event.new(*args).payload
      trace << [:instrument, payload[:action]]
      notifications << notification_signature(payload)
    end
    yield
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    clear_record_hooks!
  end

  def hook_signature(payload)
    assert_equal payload[:recording].recordable_id, payload[:recordable]&.id
    {
      action: payload[:action],
      recordable_id: :page,
      recording_id: :recording,
      root_recording_id: payload[:root_recording]&.id,
      parent_recording: payload[:parent_recording],
      actor_id: payload[:actor]&.id,
      impersonator_id: payload[:impersonator]&.id,
      metadata: payload[:metadata].deep_stringify_keys
    }
  end

  def after_signature(event)
    comparable_event(event).merge("action" => event.action)
  end

  def notification_signature(payload)
    assert_equal payload[:recordable_id], payload[:previous_recordable_id]
    {
      schema_version: payload[:schema_version],
      action: payload[:action],
      recordable_type: payload[:recordable_type],
      previous_recordable_type: payload[:previous_recordable_type],
      previous_recordable_id: :page,
      actor_type: payload[:actor_type],
      actor_id: payload[:actor_id],
      impersonator_type: payload[:impersonator_type],
      impersonator_id: payload[:impersonator_id],
      occurred_at: payload[:occurred_at].iso8601(6),
      metadata: payload[:metadata],
      root_recording_id: payload[:root_recording_id],
      recording_id: :recording,
      frozen_metadata: payload[:metadata].frozen?
    }
  end

  def assert_target_lock(rows, ordered, root)
    locks = rows.select { |row| row[:sql].match?(/FOR UPDATE/) }
    locked_ids = locks.fetch(0).fetch(:binds).map(&:to_s)

    assert_equal 1, locks.size
    assert_match(/ORDER BY/i, locks.fetch(0).fetch(:sql))
    assert_equal ordered.map { |recording| recording.id.to_s }.sort, locked_ids.sort
    refute_includes locked_ids, root.id.to_s
    refute(rows.any? { |row| row[:sql].match?(/FOR SHARE/) })
  end

  def statements_for(entries)
    statement_rows(entries).map { |row| row[:sql] }
  end

  def statement_rows(entries)
    captured = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if sql.match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE|ROLLBACK)\b/i)

      captured << { sql: sql, binds: bind_values(payload) }
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      RecordingStudio.record_events!(entries)
    end
    captured
  end

  def bind_values(payload)
    values = payload[:type_casted_binds]
    values = values.call if values.respond_to?(:call)
    Array(values || payload[:binds]).map { |bind| bind.respond_to?(:value) ? bind.value : bind }
  end

  def clear_record_hooks!
    RecordingStudio.configuration.hooks.clear(:before_record)
    RecordingStudio.configuration.hooks.clear(:after_record)
  end

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.root_recording_for(workspace)]
  end

  def create_page(root, title)
    RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: title),
      root_recording: root,
      parent_recording: root
    ).recording
  end

  def create_user(name, email)
    User.create!(name: name, email: email, password: "password123", password_confirmation: "password123")
  end
end
