# frozen_string_literal: true

require "test_helper"

class RecordingApiTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_actor = RecordingStudio.configuration.actor
    @original_idempotency_mode = RecordingStudio.configuration.idempotency_mode
    @original_notifications = RecordingStudio.configuration.event_notifications_enabled

    RecordingStudio.configuration.recordable_types = %w[RecordingStudioPage RecordingStudioComment]
    RecordingStudio.configuration.actor = -> {}
    RecordingStudio.configuration.idempotency_mode = :return_existing
    RecordingStudio.configuration.event_notifications_enabled = true

    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudioPage.delete_all
    RecordingStudioComment.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.actor = @original_actor
    RecordingStudio.configuration.idempotency_mode = @original_idempotency_mode
    RecordingStudio.configuration.event_notifications_enabled = @original_notifications
  end

  def test_record_creates_recording_and_event
    workspace = Workspace.create!(name: "Workspace")
    page = RecordingStudioPage.new(title: "Hello")

    event = RecordingStudio.record!(
      action: "created",
      recordable: page,
      container: workspace,
      metadata: { "source" => "test" }
    )

    assert_instance_of RecordingStudio::Event, event
    assert_equal "created", event.action
    assert_equal page, event.recordable
    assert_equal workspace, event.recording.container
    assert_nil event.previous_recordable
    assert_equal({ "source" => "test" }, event.metadata)
  end

  def test_record_raises_when_container_missing
    page = RecordingStudioPage.new(title: "Hello")

    assert_raises(ArgumentError) do
      RecordingStudio.record!(action: "created", recordable: page, container: nil)
    end
  end

  def test_record_uses_actor_when_actor_missing
    workspace = Workspace.create!(name: "Workspace")
    user = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    RecordingStudio.configuration.actor = -> { user }

    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                                    container: workspace)

    assert_equal user, event.actor
  end

  def test_record_uses_impersonator_from_configuration
    workspace = Workspace.create!(name: "Workspace")
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    impersonator = User.create!(name: "Admin", email: "admin@example.com", password: "password123")
    RecordingStudio.configuration.actor = -> { actor }
    RecordingStudio.configuration.impersonator = -> { impersonator }

    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                                    container: workspace)

    assert_equal actor, event.actor
    assert_equal impersonator, event.impersonator
  end

  def test_record_impersonator_explicitly_overrides_configuration
    workspace = Workspace.create!(name: "Workspace")
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    impersonator = User.create!(name: "Admin", email: "admin@example.com", password: "password123")
    override = User.create!(name: "Override", email: "override@example.com", password: "password123")
    RecordingStudio.configuration.actor = -> { actor }
    RecordingStudio.configuration.impersonator = -> { impersonator }

    event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Hello"),
      container: workspace,
      impersonator: override
    )

    assert_equal actor, event.actor
    assert_equal override, event.impersonator
  end

  def test_record_rejects_recordable_type_change
    workspace = Workspace.create!(name: "Workspace")
    initial_event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                                            container: workspace)
    recording = initial_event.recording

    assert_raises(ArgumentError) do
      RecordingStudio.record!(
        action: "updated",
        recordable: RecordingStudioComment.create!(body: "Note"),
        recording: recording,
        container: workspace
      )
    end
  end

  def test_record_rejects_parent_recording_from_other_container
    workspace = Workspace.create!(name: "Workspace")
    other_workspace = Workspace.create!(name: "Other Workspace")

    foreign_parent = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Foreign"),
      container: other_workspace
    ).recording

    assert_raises(ArgumentError) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "Child"),
        container: workspace,
        parent_recording: foreign_parent
      )
    end
  end

  def test_record_rejects_recording_when_container_mismatch
    workspace = Workspace.create!(name: "Workspace")
    other_workspace = Workspace.create!(name: "Other Workspace")

    recording = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      container: workspace
    ).recording

    assert_raises(ArgumentError) do
      RecordingStudio.record!(
        action: "updated",
        recordable: recording.recordable,
        recording: recording,
        container: other_workspace
      )
    end
  end

  def test_record_normalizes_metadata
    workspace = Workspace.create!(name: "Workspace")

    event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Hello"),
      container: workspace,
      metadata: nil
    )

    assert_equal({}, event.metadata)
  end

  def test_idempotency_returns_existing_event
    workspace = Workspace.create!(name: "Workspace")
    first_event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                                          container: workspace)
    recording = first_event.recording

    second_event = RecordingStudio.record!(
      action: "updated",
      recordable: recording.recordable,
      recording: recording,
      container: workspace,
      idempotency_key: "abc"
    )

    duplicate_event = RecordingStudio.record!(
      action: "updated",
      recordable: recording.recordable,
      recording: recording,
      container: workspace,
      idempotency_key: "abc"
    )

    assert_equal second_event.id, duplicate_event.id
  end

  def test_idempotency_raises_when_configured
    workspace = Workspace.create!(name: "Workspace")
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                                    container: workspace)
    recording = event.recording
    RecordingStudio.configuration.idempotency_mode = :raise

    RecordingStudio.record!(
      action: "updated",
      recordable: recording.recordable,
      recording: recording,
      container: workspace,
      idempotency_key: "xyz"
    )

    assert_raises(RecordingStudio::IdempotencyError) do
      RecordingStudio.record!(
        action: "updated",
        recordable: recording.recordable,
        recording: recording,
        container: workspace,
        idempotency_key: "xyz"
      )
    end
  end

  def test_idempotency_error_masks_key
    workspace = Workspace.create!(name: "Workspace")
    event = RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                                    container: workspace)
    recording = event.recording
    RecordingStudio.configuration.idempotency_mode = :raise

    RecordingStudio.record!(
      action: "updated",
      recordable: recording.recordable,
      recording: recording,
      container: workspace,
      idempotency_key: "abcdef"
    )

    error = assert_raises(RecordingStudio::IdempotencyError) do
      RecordingStudio.record!(
        action: "updated",
        recordable: recording.recordable,
        recording: recording,
        container: workspace,
        idempotency_key: "abcdef"
      )
    end

    assert_includes error.message, "****cdef"
  end

  def test_event_notifications_fire_when_enabled
    workspace = Workspace.create!(name: "Workspace")
    events = []

    subscriber = ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                            container: workspace)

    assert_equal 1, events.size
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_event_notification_payload_includes_impersonator
    workspace = Workspace.create!(name: "Workspace")
    actor = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    impersonator = User.create!(name: "Admin", email: "admin@example.com", password: "password123")
    events = []

    subscriber = ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Hello"),
      container: workspace,
      actor: actor,
      impersonator: impersonator
    )

    payload = events.first.payload
    assert_equal impersonator.id, payload[:impersonator_id]
    assert_equal impersonator.class.name, payload[:impersonator_type]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_event_notifications_skip_when_disabled
    workspace = Workspace.create!(name: "Workspace")
    RecordingStudio.configuration.event_notifications_enabled = false
    events = []

    subscriber = ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    RecordingStudio.record!(action: "created", recordable: RecordingStudioPage.new(title: "Hello"),
                            container: workspace)

    assert_empty events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
