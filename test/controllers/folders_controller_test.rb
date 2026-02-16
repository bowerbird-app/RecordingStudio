# frozen_string_literal: true

require "test_helper"
require "securerandom"

class FoldersControllerTest < ActionDispatch::IntegrationTest
  MODERN_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

  setup do
    unique = SecureRandom.hex(8)

    @admin = User.create!(
      name: "Admin",
      email: "admin-folders-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @viewer = User.create!(
      name: "Viewer",
      email: "viewer-folders-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @workspace = Workspace.create!(name: "Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: @workspace)

    grant_root_access(@root_recording, @admin, :admin)
    grant_root_access(@root_recording, @viewer, :view)

    folder = RecordingStudioFolder.create!(name: "Projects")
    @folder_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @root_recording,
      recordable: folder
    )
  end

  test "non-admin cannot add boundary" do
    sign_in_as(@viewer)

    assert_no_difference(["RecordingStudio::AccessBoundary.count", "RecordingStudio::Recording.count"]) do
      post boundary_recordings_path,
           params: { parent_recording_id: @folder_recording.id, minimum_role: "edit" },
           headers: { "User-Agent" => MODERN_UA }
    end

    assert_redirected_to folder_path(@folder_recording)
    assert_equal "You are not authorized to view this page.", flash[:alert]
  end

  test "non-admin cannot view boundary edit page" do
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :view)
    boundary_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @folder_recording,
      recordable: boundary
    )

    sign_in_as(@viewer)

    get edit_boundary_recording_path(boundary_recording), headers: { "User-Agent" => MODERN_UA }

    assert_redirected_to folder_path(@folder_recording)
    assert_equal "You are not authorized to view this page.", flash[:alert]
  end

  test "admin can view boundary edit page" do
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :view)
    boundary_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @folder_recording,
      recordable: boundary
    )

    sign_in_as(@admin)

    get edit_boundary_recording_path(boundary_recording), headers: { "User-Agent" => MODERN_UA }

    assert_response :success
    assert_includes @response.body, "Boundary access"
    assert_includes @response.body, "Add users/actors below this boundary"
  end

  test "non-admin cannot remove boundary" do
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :view)
    boundary_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @folder_recording,
      recordable: boundary
    )

    sign_in_as(@viewer)

    assert_no_difference(["RecordingStudio::AccessBoundary.count", "RecordingStudio::Recording.count"]) do
      delete boundary_recording_path(boundary_recording), headers: { "User-Agent" => MODERN_UA }
    end

    assert_redirected_to folder_path(@folder_recording)
    assert_equal "You are not authorized to view this page.", flash[:alert]
    assert RecordingStudio::Recording.exists?(boundary_recording.id)
  end

  test "non-admin cannot update boundary" do
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :view)
    boundary_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @folder_recording,
      recordable: boundary
    )

    sign_in_as(@viewer)

    patch boundary_recording_path(boundary_recording),
          params: { minimum_role: "admin" },
          headers: { "User-Agent" => MODERN_UA }

    assert_redirected_to folder_path(@folder_recording)
    assert_equal "You are not authorized to view this page.", flash[:alert]
    assert_equal "view", boundary_recording.reload.recordable.minimum_role
  end

  test "admin can update boundary minimum role" do
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :view)
    boundary_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @folder_recording,
      recordable: boundary
    )
    previous_recordable_id = boundary_recording.recordable_id

    sign_in_as(@admin)

    patch boundary_recording_path(boundary_recording),
          params: { minimum_role: "edit" },
          headers: { "User-Agent" => MODERN_UA }

    assert_redirected_to folder_path(@folder_recording)
    assert_equal "Boundary updated.", flash[:notice]
    assert_equal "edit", boundary_recording.reload.recordable.minimum_role
    assert_not_equal previous_recordable_id, boundary_recording.recordable_id
    assert_equal "view", RecordingStudio::AccessBoundary.find(previous_recordable_id).minimum_role
  end

  test "admin remove boundary soft deletes recording" do
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :view)
    boundary_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      parent_recording: @folder_recording,
      recordable: boundary
    )

    sign_in_as(@admin)

    delete boundary_recording_path(boundary_recording), headers: { "User-Agent" => MODERN_UA }

    assert_redirected_to folder_path(@folder_recording)
    assert_equal "Boundary removed.", flash[:notice]
    assert_not_nil RecordingStudio::Recording.unscoped.find(boundary_recording.id).trashed_at
    assert RecordingStudio::AccessBoundary.exists?(boundary.id)
  end

  test "index only lists folders in accessible roots" do
    private_workspace = Workspace.create!(name: "Private")
    private_root = RecordingStudio::Recording.create!(recordable: private_workspace)
    private_folder = RecordingStudioFolder.create!(name: "Secret Folder")
    RecordingStudio::Recording.create!(
      root_recording: private_root,
      parent_recording: private_root,
      recordable: private_folder
    )

    sign_in_as(@viewer)

    get folders_path, headers: { "User-Agent" => MODERN_UA }

    assert_response :success
    assert_includes @response.body, "Projects"
    assert_not_includes @response.body, "Secret Folder"
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
