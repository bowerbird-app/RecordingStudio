# frozen_string_literal: true

require "test_helper"

class RecordingApiTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_actor = RecordingStudio.configuration.actor
    @original_idempotency_mode = RecordingStudio.configuration.idempotency_mode
    @original_notifications = RecordingStudio.configuration.event_notifications_enabled

    RecordingStudio.configuration.recordable_types = ["Page", "Comment"]
    RecordingStudio.configuration.actor = -> { nil }
    RecordingStudio.configuration.idempotency_mode = :return_existing
    RecordingStudio.configuration.event_notifications_enabled = true

    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    Page.delete_all
    Comment.delete_all
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
    page = Page.new(title: "Hello")

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
    page = Page.new(title: "Hello")

    assert_raises(ArgumentError) do
      RecordingStudio.record!(action: "created", recordable: page, container: nil)
    end
  end

  def test_record_uses_actor_when_actor_missing
    workspace = Workspace.create!(name: "Workspace")
    user = User.create!(name: "Actor", email: "actor@example.com", password: "password123")
    RecordingStudio.configuration.actor = -> { user }

    event = RecordingStudio.record!(action: "created", recordable: Page.new(title: "Hello"), container: workspace)

    assert_equal user, event.actor
  end

  def test_record_rejects_recordable_type_change
    workspace = Workspace.create!(name: "Workspace")
    initial_event = RecordingStudio.record!(action: "created", recordable: Page.new(title: "Hello"), container: workspace)
    recording = initial_event.recording

    assert_raises(ArgumentError) do
      RecordingStudio.record!(
        action: "updated",
        recordable: Comment.create!(body: "Note"),
        recording: recording,
        container: workspace
      )
    end
  end

  def test_record_normalizes_metadata
    workspace = Workspace.create!(name: "Workspace")

    event = RecordingStudio.record!(action: "created", recordable: Page.new(title: "Hello"), container: workspace, metadata: nil)

    assert_equal({}, event.metadata)
  end

  def test_idempotency_returns_existing_event
    workspace = Workspace.create!(name: "Workspace")
    first_event = RecordingStudio.record!(action: "created", recordable: Page.new(title: "Hello"), container: workspace)
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
    event = RecordingStudio.record!(action: "created", recordable: Page.new(title: "Hello"), container: workspace)
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

  def test_event_notifications_fire_when_enabled
    workspace = Workspace.create!(name: "Workspace")
    events = []

    subscriber = ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    RecordingStudio.record!(action: "created", recordable: Page.new(title: "Hello"), container: workspace)

    assert_equal 1, events.size
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

    RecordingStudio.record!(action: "created", recordable: Page.new(title: "Hello"), container: workspace)

    assert_empty events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
