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
    assert_select "html[data-theme=rounded] body[data-recording-studio-default-layout=true]", count: 1
    assert_select "body[data-theme]", count: 0
    assert_select "header nav[aria-label='Page navigation']", count: 1
    assert_select "a[href='#{root_path}'][aria-label='Home']", count: 1
    assert_select "header .fp-button-group-menu", count: 1
    assert_select "header .fp-button-group-menu__row a[href='#{new_workspace_path}']", text: "Add workspace", count: 1
    assert_select "header .fp-button-group-menu__panel a[href='#{new_workspace_path}']", text: "Add workspace", count: 1
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

  test "show registers page actions once inside the top nav" do
    get workspace_path(@workspace), headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "[data-flat-pack-content-scroll=below] header.fp-top-nav[data-fp-top-nav-padding=none]", count: 1
    assert_select "[data-flat-pack--top-nav-target='toggle']", count: 0
    assert_select "header nav[aria-label='Page navigation']", count: 1
    assert_select "a[href='#{workspaces_path}'][aria-label='Workspaces'][class*='button-round-border-radius']", count: 1
    assert_select "header nav a[href='#{root_path}'][aria-label='Home'][class*='button-round-border-radius']", count: 1
    assert_select "header .fp-button-group-menu[data-variant=outlined]", count: 1
    assert_select "header .fp-button-group-menu__trigger", count: 1
    assert_select "header .fp-button-group-menu__row" do
      assert_select "a[href='#{workspace_pages_path(@workspace)}']", text: "Browse Pages", count: 1
      assert_select "a[href='#{new_workspace_page_path(@workspace)}'][data-fp-style=ghost]", text: "New Page", count: 1
      assert_select "a[href='#{recordings_path}']", text: "Browse Recordings", count: 1
    end
    assert_select "header .fp-button-group-menu__panel" do
      assert_select "a[href='#{workspace_pages_path(@workspace)}']", text: "Browse Pages", count: 1
      assert_select "a[href='#{new_workspace_page_path(@workspace)}']", text: "New Page", count: 1
      assert_select "a[href='#{recordings_path}']", text: "Browse Recordings", count: 1
    end
    assert_select "main .fp-button-group-menu", count: 0
    assert_select "main h1", text: @workspace.name
    assert_select "a", text: "Delete", count: 0
    assert_not_includes @response.body, "flat-pack--breadcrumb"
  end

  test "show pads the hierarchy card header" do
    get workspace_path(@workspace), headers: modern_headers

    assert_response :success
    assert_select ".fp-card .fp-section-title", text: /Recording hierarchy/
    assert_includes @response.body, "p-[var(--card-padding-md)]"
    assert_not_includes @response.body, 'data-fp-card-padding="none"'
    assert_not_includes @response.body, "my-8"
  end

  test "new shows only the back button when nothing is registered" do
    get new_workspace_path, headers: modern_headers

    assert_response :success
    assert_select "[data-fp-page-layout-width=default][data-fp-page-layout-top-nav-width=content]", count: 1
    assert_select "[data-flat-pack-content-scroll=below]", count: 1
    assert_select "header nav[aria-label='Page navigation']", count: 1
    assert_select "a[href='#{workspaces_path}'][aria-label='Workspaces'][class*='button-round-border-radius']", count: 1
    assert_select ".fp-button-group-menu", count: 0
    assert_select "[data-flat-pack--top-nav-target='toggle']", count: 0
    assert_includes @response.body, "Create a container for recordings."
    assert_select "ul.flex.flex-wrap.gap-2 button", text: "Create Workspace", count: 1
    assert_select "ul.flex.flex-wrap.gap-2 a", text: "Cancel", count: 1
    assert_select ".md\\:grid-cols-2", count: 0
  end
end
