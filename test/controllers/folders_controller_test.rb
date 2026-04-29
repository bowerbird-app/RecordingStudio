# frozen_string_literal: true

require "test_helper"

class FoldersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Folder Author")
    @workspace = Workspace.create!(name: "Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: @workspace)
    folder = RecordingStudioFolder.create!(name: "Projects")
    @folder_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @root_recording,
      recordable: folder
    )

    child_page = RecordingStudioPage.create!(title: "Roadmap")
    RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @folder_recording,
      recordable: child_page
    )

    sign_in_as(@user)
  end

  test "index lists folders across workspaces" do
    other_root = RecordingStudio::Recording.create!(recordable: Workspace.create!(name: "Other Workspace"))
    RecordingStudio::Recording.create!(
      root_recording: other_root,
      parent_recording: other_root,
      recordable: RecordingStudioFolder.create!(name: "Archive")
    )

    get folders_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Projects"
    assert_includes @response.body, "Archive"
  end

  test "show renders child recordings" do
    get folder_path(@folder_recording), headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Roadmap"
    assert_includes @response.body, "Folder recording details and children"
  end
end
