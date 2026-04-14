# frozen_string_literal: true

require "test_helper"

class CapabilitiesTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_feature_flags = RecordingStudio.features.to_h
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioFolder
      RecordingStudioComment
      RecordingStudio::Access
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    RecordingStudio.apply_capabilities!

    RecordingStudio::Event.delete_all
    RecordingStudio::DeviceSession.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudio::Access.delete_all
    RecordingStudioPage.delete_all
    RecordingStudioFolder.delete_all
    RecordingStudioComment.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    @original_feature_flags.each do |feature_name, value|
      RecordingStudio.features.public_send("#{feature_name}=", value)
    end

    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::DelegatedTypeRegistrar.apply!
  end

  def test_page_commentable_api_creates_and_lists_comment_recordings
    _, root = create_workspace_root
    actor = create_user("commenter@example.com")
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: root) do |page|
      page.title = "Discuss"
    end

    comment_recording = page_recording.comment!(body: "Great work!", actor: actor, metadata: { source: "test" })

    assert_equal "Great work!", comment_recording.recordable.body
    assert_equal [comment_recording.id], page_recording.comments.pluck(:id)
  end

  def test_commentable_is_opt_in_per_recordable_type
    _, root = create_workspace_root
    actor = create_user("folder-commenter@example.com")
    folder_recording = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Folder"
    end

    error = assert_raises(RecordingStudio::CapabilityDisabled) do
      folder_recording.comment!(body: "Not allowed", actor: actor)
    end
    assert_match(/Capability :commentable is not enabled/, error.message)
  end

  def test_commentable_behavior_is_invoked_from_recording_surface
    _, root = create_workspace_root
    actor = create_user("recording-surface@example.com")
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: root) do |page|
      page.title = "Discuss"
    end

    assert page_recording.respond_to?(:comment!)
    refute page_recording.recordable.respond_to?(:comment!)
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    root = RecordingStudio::Recording.create!(recordable: workspace)
    [workspace, root]
  end

  def create_user(email)
    User.create!(name: email.split("@").first, email: email, password: "password123")
  end

  def grant_root_access(root:, actor:, role:)
    root.record(RecordingStudio::Access, actor: actor, parent_recording: root) do |access|
      access.actor = actor
      access.role = role
    end
  end

  def grant_access(recording:, actor:, role:)
    recording.root_recording.record(RecordingStudio::Access, actor: actor, parent_recording: recording) do |access|
      access.actor = actor
      access.role = role
    end
  end
end
