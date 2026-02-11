# frozen_string_literal: true

require "test_helper"
require "securerandom"

class AccessRecordingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    unique = SecureRandom.hex(8)

    @admin = User.create!(
      name: "Admin",
      email: "admin-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @target = User.create!(
      name: "Target",
      email: "target-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @workspace = Workspace.create!(name: "Workspace")

    admin_access = RecordingStudio::Access.create!(actor: @admin, role: :admin)
    RecordingStudio::Recording.create!(container: @workspace, recordable: admin_access, parent_recording: nil)

    target_access = RecordingStudio::Access.create!(actor: @target, role: :view)
    @target_access_recording = RecordingStudio::Recording.create!(
      container: @workspace,
      recordable: target_access,
      parent_recording: nil
    )
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password" } }
    assert_response :redirect
  end

  test "admin can edit container-level access role by revising recording" do
    sign_in_as @admin

    previous_recordable_id = @target_access_recording.recordable_id

    assert_difference("RecordingStudio::Access.count", +1) do
      patch access_recording_path(@target_access_recording), params: { access: { role: "edit" } }
    end

    assert_redirected_to workspace_path(@workspace)

    @target_access_recording.reload
    assert_not_equal previous_recordable_id, @target_access_recording.recordable_id
    assert_equal "edit", @target_access_recording.recordable.role
  end

  test "non-admin cannot edit container-level access" do
    unique = SecureRandom.hex(8)

    viewer = User.create!(
      name: "Viewer",
      email: "viewer-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    viewer_access = RecordingStudio::Access.create!(actor: viewer, role: :view)
    RecordingStudio::Recording.create!(container: @workspace, recordable: viewer_access, parent_recording: nil)

    sign_in_as viewer

    previous_recordable_id = @target_access_recording.recordable_id

    assert_no_difference("RecordingStudio::Access.count") do
      patch access_recording_path(@target_access_recording), params: { access: { role: "admin" } }
    end

    assert_redirected_to workspace_path(@workspace)

    @target_access_recording.reload
    assert_equal previous_recordable_id, @target_access_recording.recordable_id
    assert_equal "view", @target_access_recording.recordable.role
  end
end
