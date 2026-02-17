# frozen_string_literal: true

require "test_helper"

class DeviceSessionTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[
      Workspace RecordingStudioPage
      RecordingStudio::Access RecordingStudio::AccessBoundary
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.unscoped.delete_all
    RecordingStudio::DeviceSession.delete_all
    RecordingStudio::Access.delete_all
    Workspace.delete_all
    User.delete_all

    @user = User.create!(name: "Alice", email: "alice@example.com", password: "password123")
    @workspace = Workspace.create!(name: "Test Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: @workspace)
    grant_root_access(@root_recording, @user, :view)

    @device_fingerprint = SecureRandom.uuid
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_resolve_creates_session_for_new_device
    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      user_agent: "Test Agent"
    )

    assert_not_nil session
    assert session.persisted?
    assert_equal @user.class.name, session.actor_type
    assert_equal @user.id, session.actor_id
    assert_equal @device_fingerprint, session.device_fingerprint
    assert_equal "Test Agent", session.user_agent
    assert_equal @root_recording.id, session.root_recording_id
  end

  def test_resolve_returns_existing_session
    first_session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    second_session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    assert_equal first_session.id, second_session.id
    assert_equal 1, RecordingStudio::DeviceSession.count
  end

  def test_resolve_returns_nil_when_no_accessible_roots
    user_without_access = User.create!(name: "Bob", email: "bob@example.com", password: "password123")

    session = RecordingStudio::DeviceSession.resolve(
      actor: user_without_access,
      device_fingerprint: @device_fingerprint
    )

    assert_nil session
  end

  def test_switch_to_updates_root_recording
    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, @user, :view)

    session.switch_to!(root_recording2)

    session.reload
    assert_equal root_recording2.id, session.root_recording_id
  end

  def test_switch_to_raises_access_denied_when_not_allowed
    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)

    assert_raises RecordingStudio::AccessDenied do
      session.switch_to!(root_recording2)
    end
  end

  def test_switch_to_validates_minimum_role
    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, @user, :view)

    assert_raises RecordingStudio::AccessDenied do
      session.switch_to!(root_recording2, minimum_role: :admin)
    end
  end

  def test_device_fingerprint_scoped_to_actor
    user2 = User.create!(name: "Bob", email: "bob@example.com", password: "password123")
    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, user2, :view)

    session1 = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    session2 = RecordingStudio::DeviceSession.resolve(
      actor: user2,
      device_fingerprint: @device_fingerprint
    )

    assert_not_equal session1.id, session2.id
    assert_equal @root_recording.id, session1.root_recording_id
    assert_equal root_recording2.id, session2.root_recording_id
  end

  def test_same_actor_different_devices
    device2 = SecureRandom.uuid

    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, @user, :view)

    session1 = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    session2 = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: device2
    )

    session1.switch_to!(root_recording2)

    session1.reload
    session2.reload

    assert_not_equal session1.id, session2.id
    assert_equal root_recording2.id, session1.root_recording_id
    assert_equal @root_recording.id, session2.root_recording_id
  end

  def test_validates_root_recording_must_be_root
    page = RecordingStudioPage.create!(title: "Page")
    child_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @root_recording,
      recordable: page
    )

    session = RecordingStudio::DeviceSession.new(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      root_recording: child_recording
    )

    assert_not session.valid?
    assert_includes session.errors[:root_recording], "must be a root recording (no parent)"
  end

  def test_validates_device_fingerprint_presence
    session = RecordingStudio::DeviceSession.new(
      actor: @user,
      root_recording: @root_recording
    )

    assert_not session.valid?
    assert_includes session.errors[:device_fingerprint], "can't be blank"
  end

  def test_validates_device_fingerprint_uniqueness_per_actor
    RecordingStudio::DeviceSession.create!(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      root_recording: @root_recording
    )

    duplicate = RecordingStudio::DeviceSession.new(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      root_recording: @root_recording
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:device_fingerprint], "has already been taken"
  end

  private

  def grant_root_access(root_recording, actor, role)
    access = RecordingStudio::Access.create!(actor: actor, role: role)
    RecordingStudio::Recording.create!(
      root_recording: root_recording,
      recordable: access,
      parent_recording: root_recording
    )
  end
end
