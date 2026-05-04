# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Page Author")
    sign_in_as(@user)

    @workspace = Workspace.create!(name: "Alpha Workspace")
    @workspace_root = RecordingStudio::Recording.create!(recordable: @workspace)
    @page_recording = @workspace_root.record(RecordingStudioPage, actor: @user) do |page|
      page.title = "Workspace Alpha Plan"
      page.summary = "Alpha summary"
    end

    @other_workspace = Workspace.create!(name: "Beta Workspace")
    @other_root = RecordingStudio::Recording.create!(recordable: @other_workspace)
    @other_page_recording = @other_root.record(RecordingStudioPage, actor: @user) do |page|
      page.title = "Workspace Beta Plan"
      page.summary = "Beta summary"
    end
  end

  test "index scopes pages to the selected workspace" do
    get workspace_pages_path(@workspace), headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Alpha Workspace Pages"
    assert_includes @response.body, @page_recording.recordable.title
    assert_not_includes @response.body, @other_page_recording.recordable.title
  end

  test "create records a page under the selected workspace root" do
    assert_difference([ "RecordingStudio::Recording.count", "RecordingStudio::Event.count", "RecordingStudioPage.count" ], 1) do
      post workspace_pages_path(@workspace),
        params: { page: { title: "New Workspace Page", summary: "Created from nested route" } },
        headers: modern_headers
    end

    created_recording = @workspace_root.reload.recordings_of(RecordingStudioPage).recent.first

    assert_redirected_to recording_path(created_recording)
    assert_equal @workspace_root.id, created_recording.root_recording_id
    assert_equal "New Workspace Page", created_recording.recordable.title
  end

  test "edit rejects a page recording from another workspace" do
    assert_raises(ActiveRecord::RecordNotFound) do
      get edit_workspace_page_path(@workspace, @other_page_recording), headers: modern_headers
    end
  end
end
