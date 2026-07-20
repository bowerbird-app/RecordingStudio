# frozen_string_literal: true

require "test_helper"

class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Workspace Author")
    @workspace = Workspace.create!(name: "Workspace")
    @root_recording = RecordingStudio.root_recording_for(@workspace)
    sign_in_as(@user)
  end

  test "index lists workspaces" do
    get workspaces_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "body[data-theme='rounded']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "a[href='#{root_path}'][aria-label='Home']", count: 1
    assert_select "a[href='#{new_workspace_path}'][aria-label='Add workspace']", count: 1
    assert_includes @response.body, @workspace.name
    assert_not_includes @response.body, "New Workspace"
    long_class = "rounded-lg overflow-visible h-full flex flex-col text-[var(--surface-content-color)] " \
                 "bg-[var(--card-background-color)] border border-[var(--card-border-color)]"
    assert_not_includes @response.body, long_class
    assert_not_includes @response.body, "flat-pack--sidebar-group"
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

  test "new renders page nav with workspaces anchor" do
    get new_workspace_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "a[href='#{workspaces_path}'][aria-label='Workspaces'], button[aria-label='Workspaces']", count: 1
    assert_includes @response.body, "Create a container for recordings."
  end
end
