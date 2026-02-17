# frozen_string_literal: true

require "test_helper"

class RootRecordingResolverTest < ActiveSupport::TestCase
  RootRecordingResolver = RecordingStudio::Services::RootRecordingResolver

  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[
      Workspace RecordingStudioPage
      RecordingStudio::Access RecordingStudio::AccessBoundary
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::DeviceSession.delete_all
    RecordingStudio::Recording.unscoped.delete_all
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

  def test_resolves_root_recording_for_actor_and_device
    result = RootRecordingResolver.call(
      actor: @user,
      device_fingerprint: @device_fingerprint,
      user_agent: "Test Agent"
    )

    assert result.success?
    assert_not_nil result.value
    assert_equal @root_recording.id, result.value.id
  end

  def test_returns_failure_when_actor_nil
    result = RootRecordingResolver.call(
      actor: nil,
      device_fingerprint: @device_fingerprint
    )

    assert result.failure?
    assert_equal "Actor is required", result.error
  end

  def test_returns_failure_when_fingerprint_blank
    result = RootRecordingResolver.call(
      actor: @user,
      device_fingerprint: ""
    )

    assert result.failure?
    assert_equal "Device fingerprint is required", result.error
  end

  def test_falls_back_when_access_revoked
    # Create initial session
    result = RootRecordingResolver.call(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )
    assert result.success?
    assert_equal @root_recording.id, result.value.id

    # Create a second workspace and grant access
    workspace2 = Workspace.create!(name: "Workspace 2")
    root_recording2 = RecordingStudio::Recording.create!(recordable: workspace2)
    grant_root_access(root_recording2, @user, :view)

    # Switch to the new workspace
    session = RecordingStudio::DeviceSession.for_actor(@user).for_device(@device_fingerprint).first
    session.update!(root_recording_id: root_recording2.id)

    # Revoke access to workspace2 by deleting all access recordings
    RecordingStudio::Recording.unscoped.where(
      recordable_type: "RecordingStudio::Access",
      root_recording_id: root_recording2.id
    ).destroy_all

    # Resolver should fall back to workspace1
    result = RootRecordingResolver.call(
      actor: @user,
      device_fingerprint: @device_fingerprint
    )

    assert result.success?
    assert_equal @root_recording.id, result.value.id

    # Verify session was updated
    session.reload
    assert_equal @root_recording.id, session.root_recording_id
  end

  def test_returns_failure_when_no_roots_at_all
    user_without_access = User.create!(name: "Bob", email: "bob@example.com", password: "password123")

    result = RootRecordingResolver.call(
      actor: user_without_access,
      device_fingerprint: @device_fingerprint
    )

    assert result.failure?
    assert_equal "No accessible root recordings found", result.error
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
