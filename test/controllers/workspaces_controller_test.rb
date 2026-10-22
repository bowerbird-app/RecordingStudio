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
    assert_select "h1", text: "Workspaces"
    assert_includes @response.body, "Choose a workspace explicitly before browsing or creating workspace-rooted pages."
    assert_select "a[href='#{new_workspace_path}']", text: "Add workspace"
    assert_select "nav a[href='#{new_workspace_path}']", count: 0
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

  test "show uses default layout page nav instead of breadcrumbs" do
    get workspace_path(@workspace), headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "a[href='#{workspaces_path}'][aria-label='Workspaces']", count: 1
    assert_select "a[href='#{root_path}'][aria-label='Home']", count: 1
    assert_select "h1", text: @workspace.name
    assert_includes @response.body, "explicit page routes and its full recording tree."
    assert_select "header[data-controller='flat-pack--top-nav']", count: 1
    desktop_nav = "[data-fp-page-nav='top_nav']"
    menu_nav = "[data-fp-page-nav='menu']"
    pages = workspace_pages_path(@workspace)
    new_page = new_workspace_page_path(@workspace)
    assert_select "#{desktop_nav} a[href='#{pages}'][data-fp-style='ghost']", text: "Browse Pages"
    assert_select "#{desktop_nav} a[href='#{new_page}'][data-fp-style='secondary']", text: "New Page"
    assert_select "#{menu_nav} a[href='#{recordings_path}'][data-fp-style='ghost']", text: "Browse Recordings"
    assert_select "#{desktop_nav} #{menu_nav}", count: 0
    assert_operator @response.body.index("New Page"), :<, @response.body.index("<h1")
    assert_select "nav a[href='#{workspace_pages_path(@workspace)}']", count: 0
    assert_not_includes @response.body, "Back to Workspaces"
    assert_not_includes @response.body, "flat-pack--breadcrumb"
  end

  test "new uses history back and keeps submit in the form" do
    get new_workspace_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
    assert_select "header[data-controller='flat-pack--top-nav']", count: 1
    assert_select "[data-fp-page-nav='menu']", count: 0
    assert_select "nav button[aria-label='Go back']", count: 1
    assert_select "a[aria-label='Workspaces']", count: 0
    assert_select "h1", text: "New Workspace"
    assert_includes @response.body, "Create a container for recordings."
    assert_select "form button", text: "Create Workspace"
    assert_select "form a[href='#{workspaces_path}']", text: "Cancel"
  end
end
