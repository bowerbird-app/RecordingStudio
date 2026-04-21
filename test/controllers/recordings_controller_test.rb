# frozen_string_literal: true

require "test_helper"

class RecordingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "User")
    sign_in_as(@user)
    workspace = Workspace.create!(name: "Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    @recording = @root_recording.record(RecordingStudioPage, actor: @user, parent_recording: @root_recording) do |page|
      page.title = "Plan"
      page.summary = "Initial draft"
    end
  end

  test "show renders recording history details" do
    get recording_path(@recording), headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Plan"
    assert_includes @response.body, "History"
    assert_includes @response.body, "Recordables"
  end

  test "log_event appends a new event" do
    assert_difference("RecordingStudio::Event.count", 1) do
      post log_event_recording_path(@recording), headers: modern_headers
    end

    assert_redirected_to recording_path(@recording)
    assert_equal "commented", @recording.reload.events.first.action
  end

  test "revert points the recording back to an earlier snapshot" do
    previous_recordable = @recording.recordable
    revised_recording = @root_recording.revise(@recording, actor: @user) do |page|
      page.title = "Updated Plan"
    end

    post revert_recording_path(revised_recording, recordable_id: previous_recordable.id), headers: modern_headers

    assert_redirected_to recording_path(revised_recording)
    assert_equal previous_recordable.id, revised_recording.reload.recordable_id
  end
end
