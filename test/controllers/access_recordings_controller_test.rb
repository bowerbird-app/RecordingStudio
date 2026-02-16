# frozen_string_literal: true

require "test_helper"
require "securerandom"

class AccessRecordingsControllerTest < ActionDispatch::IntegrationTest
  MODERN_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

  setup do
    unique = SecureRandom.hex(8)

    @admin = User.create!(
      name: "Admin",
      email: "admin-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @target = User.create!(
      name: "Target",
      email: "target-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    @workspace = Workspace.create!(name: "Workspace")
    @root_recording = RecordingStudio::Recording.create!(recordable: @workspace)

    admin_access = RecordingStudio::Access.create!(actor: @admin, role: :admin)
    RecordingStudio::Recording.create!(root_recording: @root_recording, recordable: admin_access,
                                       parent_recording: @root_recording)

    target_access = RecordingStudio::Access.create!(actor: @target, role: :view)
    @target_access_recording = RecordingStudio::Recording.create!(
      root_recording: @root_recording,
      recordable: target_access,
      parent_recording: @root_recording
    )
  end

  def sign_in_as(user)
    post user_session_path,
         params: { user: { email: user.email, password: "password" } },
         headers: { "User-Agent" => MODERN_UA }
    assert_response :redirect
  end

  test "admin can edit root-level access role by revising recording" do
    sign_in_as @admin

    previous_recordable_id = @target_access_recording.recordable_id

    assert_difference("RecordingStudio::Access.count", +1) do
      patch access_recording_path(@target_access_recording),
            params: { access: { role: "edit" } },
            headers: { "User-Agent" => MODERN_UA }
    end

    assert_redirected_to workspace_path(@workspace)

    @target_access_recording.reload
    assert_not_equal previous_recordable_id, @target_access_recording.recordable_id
    assert_equal "edit", @target_access_recording.recordable.role
  end

  test "edit page does not duplicate workspace breadcrumb for root-level access" do
    sign_in_as @admin

    get edit_access_recording_path(@target_access_recording), headers: { "User-Agent" => MODERN_UA }

    assert_response :success
    assert_includes @response.body, %(href="#{workspace_path(@workspace)}")
    assert_not_includes @response.body, %(href="#{recording_path(@root_recording)}")
  end

  test "admin can add root-level access" do
    sign_in_as @admin

    new_user = create_user(name: "New User", email_prefix: "new-user")

    create_root_access_for(user: new_user, role: "view")

    created = latest_root_access_recording
    assert_access_recording(created: created, role: "view", actor: new_user)
  end

  test "admin cannot add duplicate root-level access for same actor" do
    sign_in_as @admin

    assert_no_difference(["RecordingStudio::Access.count", "RecordingStudio::Recording.count"]) do
      post access_recordings_path,
           params: {
             root_recording_id: @root_recording.id,
             return_to: workspace_path(@workspace),
             access: {
               actor_key: "User:#{@target.id}",
               role: "admin"
             }
           },
           headers: { "User-Agent" => MODERN_UA }
    end

    assert_response :unprocessable_entity
    assert_includes @response.body, "Actor already has access."
  end

  test "non-admin cannot add root-level access" do
    unique = SecureRandom.hex(8)

    viewer = User.create!(
      name: "Viewer",
      email: "viewer-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    viewer_access = RecordingStudio::Access.create!(actor: viewer, role: :view)
    RecordingStudio::Recording.create!(root_recording: @root_recording, recordable: viewer_access,
                                       parent_recording: @root_recording)

    sign_in_as viewer

    assert_no_difference(["RecordingStudio::Access.count", "RecordingStudio::Recording.count"]) do
      post access_recordings_path,
           params: {
             root_recording_id: @root_recording.id,
             return_to: workspace_path(@workspace),
             access: {
               actor_key: "User:#{@target.id}",
               role: "admin"
             }
           },
           headers: { "User-Agent" => MODERN_UA }
    end

    assert_redirected_to workspace_path(@workspace)
  end

  test "non-admin cannot edit root-level access" do
    unique = SecureRandom.hex(8)

    viewer = User.create!(
      name: "Viewer",
      email: "viewer-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    viewer_access = RecordingStudio::Access.create!(actor: viewer, role: :view)
    RecordingStudio::Recording.create!(root_recording: @root_recording, recordable: viewer_access,
                                       parent_recording: @root_recording)

    sign_in_as viewer

    previous_recordable_id = @target_access_recording.recordable_id

    assert_no_difference("RecordingStudio::Access.count") do
      patch access_recording_path(@target_access_recording),
            params: { access: { role: "admin" } },
            headers: { "User-Agent" => MODERN_UA }
    end

    assert_redirected_to workspace_path(@workspace)

    @target_access_recording.reload
    assert_equal previous_recordable_id, @target_access_recording.recordable_id
    assert_equal "view", @target_access_recording.recordable.role
  end

  private

  def create_user(name:, email_prefix:)
    unique = SecureRandom.hex(8)
    User.create!(
      name: name,
      email: "#{email_prefix}-#{unique}@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  def create_root_access_for(user:, role:)
    assert_difference(["RecordingStudio::Access.count", "RecordingStudio::Recording.count"], +1) do
      post access_recordings_path,
           params: {
             root_recording_id: @root_recording.id,
             return_to: workspace_path(@workspace),
             access: {
               actor_key: "User:#{user.id}",
               role: role
             }
           },
           headers: { "User-Agent" => MODERN_UA }
    end

    assert_redirected_to workspace_path(@workspace)
  end

  def latest_root_access_recording
    RecordingStudio::Recording
      .for_root(@root_recording.id)
      .where(parent_recording_id: @root_recording.id, recordable_type: "RecordingStudio::Access")
      .order(created_at: :desc)
      .first
  end

  def assert_access_recording(created:, role:, actor:)
    assert_equal "RecordingStudio::Access", created.recordable_type
    assert_equal role, created.recordable.role
    assert_equal actor, created.recordable.actor
  end
end
