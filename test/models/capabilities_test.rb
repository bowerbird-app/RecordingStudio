# frozen_string_literal: true

require "test_helper"

class CapabilitiesTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioFolder
      RecordingStudioComment
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    RecordingStudio.apply_capabilities!

    reset_recording_studio_tables!(RecordingStudioPage, RecordingStudioFolder, RecordingStudioComment)
  end

  def teardown
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

  def test_trashable_is_opt_in_for_target_recording_type
    _, root = create_workspace_root
    actor = create_user("trash-capability@example.com")
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: root) do |page|
      page.title = "Trashed"
    end
    comment_recording = root.record(RecordingStudioComment, actor: actor, parent_recording: root) do |comment|
      comment.body = "Not trashable"
    end

    root.trash(page_recording, impersonator: nil)

    assert page_recording.reload.trashed_at

    error = assert_raises(RecordingStudio::CapabilityDisabled) do
      root.trash(comment_recording, impersonator: nil)
    end
    assert_match(/Capability :trashable is not enabled/, error.message)
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
end
