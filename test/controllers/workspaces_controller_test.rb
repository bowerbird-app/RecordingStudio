# frozen_string_literal: true

require "test_helper"
require "securerandom"

class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  MODERN_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

  setup do
    unique = SecureRandom.hex(8)

    @admin = User.create!(
      name: "Admin",
      email: "admin-workspaces-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @viewer = User.create!(
      name: "Viewer",
      email: "viewer-workspaces-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @workspace = Workspace.create!(name: "Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: @workspace)

    grant_root_access(@root_recording, @admin, :admin)
    grant_root_access(@root_recording, @viewer, :view)
  end

  test "non-admin cannot destroy workspace" do
    sign_in_as(@viewer)

    delete workspace_path(@workspace), headers: { "User-Agent" => MODERN_UA }

    assert_response :forbidden
    assert_nil @root_recording.reload.trashed_at
  end

  test "admin can destroy workspace" do
    sign_in_as(@admin)

    delete workspace_path(@workspace), headers: { "User-Agent" => MODERN_UA }

    assert_redirected_to workspaces_path
    assert_not_nil @root_recording.reload.trashed_at
  end

  private

  def sign_in_as(user)
    post user_session_path,
         params: { user: { email: user.email, password: "password" } },
         headers: { "User-Agent" => MODERN_UA }
    assert_response :redirect
  end

  def grant_root_access(root_recording, actor, role)
    access = RecordingStudio::Access.create!(actor: actor, role: role)
    RecordingStudio::Recording.create!(
      root_recording: root_recording,
      parent_recording: root_recording,
      recordable: access
    )
  end
end
