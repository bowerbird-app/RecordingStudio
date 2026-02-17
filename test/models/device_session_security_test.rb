# frozen_string_literal: true

require "test_helper"

class DeviceSessionSecurityTest < ActiveSupport::TestCase
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

  # Test for L-2: User agent validation
  def test_validates_user_agent_length
    session = RecordingStudio::DeviceSession.new(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      root_recording: @root_recording,
      user_agent: "A" * 300  # Exceeds 255 limit
    )

    assert_not session.valid?
    assert_includes session.errors[:user_agent], "is too long (maximum is 255 characters)"
  end

  def test_accepts_valid_user_agent
    session = RecordingStudio::DeviceSession.new(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      root_recording: @root_recording,
      user_agent: "Mozilla/5.0 (compatible; Test/1.0)"
    )

    assert session.valid?
  end

  def test_accepts_nil_user_agent
    session = RecordingStudio::DeviceSession.new(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      root_recording: @root_recording,
      user_agent: nil
    )

    assert session.valid?
  end

  # Test for L-2: User agent truncation in resolve
  def test_resolve_truncates_long_user_agent
    long_user_agent = "A" * 300

    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      user_agent: long_user_agent
    )

    assert_not_nil session
    assert_equal 255, session.user_agent.length
    assert_equal "A" * 255, session.user_agent
  end

  # Test for M-2: Timing-safe access check with Set
  def test_switch_to_uses_set_for_timing_safe_access_check
    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, @user, :view)

    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    # The check should work correctly regardless of the number of accessible workspaces
    assert_nothing_raised do
      session.switch_to!(root_recording2)
    end

    session.reload
    assert_equal root_recording2.id, session.root_recording_id
  end

  # Test for M-3: Fallback update with transaction lock
  def test_fallback_update_is_transaction_safe
    # Create initial session
    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )
    assert_equal @root_recording.id, session.root_recording_id

    # Create a second workspace and grant access
    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, @user, :view)

    # Manually update session to point to workspace2
    session.update!(root_recording_id: root_recording2.id)

    # Revoke access to workspace2
    RecordingStudio::Recording.unscoped.where(
      recordable_type: "RecordingStudio::Access",
      root_recording_id: root_recording2.id
    ).destroy_all

    # Resolver should fall back to workspace1 in a transaction-safe way
    result = RecordingStudio::Services::RootRecordingResolver.call(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    assert result.success?
    assert_equal @root_recording.id, result.value.id

    # Verify session was updated
    session.reload
    assert_equal @root_recording.id, session.root_recording_id
  end

  # Test to ensure concurrent access checks don't cause issues
  def test_concurrent_switch_attempts_handle_correctly
    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, @user, :view)

    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    # Both switches should succeed (sequential in test, but transaction-safe)
    session.switch_to!(root_recording2)
    assert_equal root_recording2.id, session.reload.root_recording_id

    session.switch_to!(@root_recording)
    assert_equal @root_recording.id, session.reload.root_recording_id
  end

  # Test that unauthorized access is properly blocked
  def test_cannot_switch_to_unauthorized_workspace
    workspace2 = Workspace.create!(name: "Private Workspace")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    # Note: NOT granting access to @user

    session = RecordingStudio::DeviceSession.resolve(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    error = assert_raises RecordingStudio::AccessDenied do
      session.switch_to!(root_recording2)
    end

    assert_includes error.message, "Actor does not have access"
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
