# frozen_string_literal: true

require_relative "../test_helper"

class PageNavDemoTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Page Nav Demo")
    sign_in_as(@user)
  end

  test "home registers page actions once in the button group" do
    get root_path, headers: modern_headers

    assert_response :success
    assert_select ".fp-button-group-menu", count: 1
    assert_select ".fp-button-group-menu[data-controller='flat-pack--button-group-menu']", count: 1
    assert_select ".fp-button-group-menu__row a[href='#{workspaces_path}']", text: "Workspaces", count: 1
    assert_select ".fp-button-group-menu__panel a[href='#{workspaces_path}']", text: "Workspaces", count: 1
    assert_select ".fp-button-group-menu__row a[href='#{layout_demo_path}']", text: "Layout Demo", count: 1
    assert_select "link[rel=stylesheet][href*='flat_pack/application']", minimum: 1
    assert_select "html[data-theme=rounded]", count: 1
    assert_select "body[data-theme]", count: 0
    assert_select "a.fp-skip-link[href='#main']", count: 1
    assert_select "main#main.fp-layout-content", count: 1
    assert_select "main#main.fp-layout-content .grid.gap-6", count: 0
    assert_select "meta[name=viewport][content*='viewport-fit=cover']", count: 1
    assert @response.body.index("flat_pack/variables") < @response.body.index("flat_pack/application")
    assert @response.body.index("flat_pack/rich_text") < @response.body.index("/tailwind")
  end

  test "folder show registers nothing and renders no empty button group" do
    workspace = Workspace.create!(name: "Folder Workspace")
    root = RecordingStudio.root_recording_for(workspace)
    recording = root.record(RecordingStudioFolder, actor: @user, parent_recording: root) do |folder|
      folder.name = "Notes"
    end

    get folder_path(recording), headers: modern_headers

    assert_response :success
    assert_select ".fp-button-group-menu", count: 0
    assert_includes @response.body, "Notes"
  end
end
