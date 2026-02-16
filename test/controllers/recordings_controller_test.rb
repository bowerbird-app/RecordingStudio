# frozen_string_literal: true

require "test_helper"
require "securerandom"

class RecordingsControllerTest < ActionDispatch::IntegrationTest
  MODERN_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

  setup do
    unique = SecureRandom.hex(8)

    @user = User.create!(
      name: "User",
      email: "user-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @viewer = User.create!(
      name: "Viewer",
      email: "viewer-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  test "show renders for folder recordable" do
    sign_in_as(@user)

    workspace = Workspace.create!(name: "Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    grant_root_access(root_recording, @user, :view)

    folder = RecordingStudioFolder.create!(name: "Projects")
    recording = RecordingStudio::Recording.create!(
      root_recording: root_recording,
      parent_recording: root_recording,
      recordable: folder
    )

    get recording_path(recording), headers: { "User-Agent" => MODERN_UA }

    assert_response :success
    assert_includes @response.body, "Projects"
    assert_includes @response.body, "Recordable Type"
    assert_includes @response.body, "Folder"
  end

  test "show forbids user without recording access" do
    workspace = Workspace.create!(name: "Private Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    grant_root_access(root_recording, @user, :view)

    folder = RecordingStudioFolder.create!(name: "Secrets")
    recording = RecordingStudio::Recording.create!(
      root_recording: root_recording,
      parent_recording: root_recording,
      recordable: folder
    )

    sign_in_as(@viewer)

    get recording_path(recording), headers: { "User-Agent" => MODERN_UA }

    assert_response :forbidden
  end

  test "log_event forbids user without edit access" do
    workspace = Workspace.create!(name: "Team Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    grant_root_access(root_recording, @user, :view)

    page = RecordingStudioPage.create!(title: "Plan")
    recording = RecordingStudio::Recording.create!(
      root_recording: root_recording,
      parent_recording: root_recording,
      recordable: page
    )

    sign_in_as(@viewer)

    assert_no_difference("RecordingStudio::Event.count") do
      post log_event_recording_path(recording), headers: { "User-Agent" => MODERN_UA }
    end

    assert_response :forbidden
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
