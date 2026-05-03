# frozen_string_literal: true

require "test_helper"

class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Workspace Author")
    @workspace = Workspace.create!(name: "Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: @workspace)
    sign_in_as(@user)
  end

  test "index lists workspaces" do
    get workspaces_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, @workspace.name
  end

  test "create also creates a root recording" do
    assert_difference(["Workspace.count", "RecordingStudio::Recording.count"], 1) do
      post workspaces_path, params: { workspace: { name: "New Workspace" } }, headers: modern_headers
    end

    created_workspace = Workspace.order(:created_at).last
    created_root = RecordingStudio::Recording.unscoped.find_by!(recordable: created_workspace, parent_recording_id: nil)

    assert_redirected_to workspaces_path
    assert_equal created_workspace, created_root.recordable
  end

end
