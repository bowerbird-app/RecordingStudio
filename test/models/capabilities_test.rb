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
      RecordingStudio::Access
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    RecordingStudio.apply_capabilities!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudio::Access.delete_all
    RecordingStudioPage.delete_all
    RecordingStudioFolder.delete_all
    RecordingStudioComment.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::DelegatedTypeRegistrar.apply!
  end

  def test_move_to_requires_capability
    _, root = create_workspace_root
    actor = create_user("mover@example.com")
    workspace_recording = root
    target_folder = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "A"
    end
    grant_root_access(root: root, actor: actor, role: :admin)

    error = assert_raises(RecordingStudio::CapabilityDisabled) do
      workspace_recording.move_to!(new_parent: target_folder, actor: actor)
    end
    assert_match(/Capability :movable is not enabled/, error.message)
  end

  def test_page_move_to_moves_and_logs_event
    _, root = create_workspace_root
    actor = create_user("editor@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    target_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Target"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Move me"
    end

    page_recording.move_to!(new_parent: target_parent, actor: actor, metadata: { reason: "reorg" })

    assert_equal target_parent.id, page_recording.reload.parent_recording_id
    event = page_recording.events.first
    assert_equal "moved", event.action
    assert_equal source_parent.id, event.metadata["from_parent_id"]
    assert_equal target_parent.id, event.metadata["to_parent_id"]
  end

  def test_page_copy_to_creates_duplicate_and_logs_source_metadata
    _, root = create_workspace_root
    actor = create_user("copier@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    target_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Target"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end

    copied = page_recording.copy_to!(new_parent: target_parent, actor: actor, metadata: { reason: "template" })

    assert_equal "Copy me", copied.recordable.title
    assert_equal target_parent.id, copied.parent_recording_id
    assert_not_equal page_recording.recordable_id, copied.recordable_id
    event = copied.events.first
    assert_equal "copied", event.action
    assert_equal page_recording.id, event.metadata["source_recording_id"]
    assert_equal page_recording.recordable_id, event.metadata["source_recordable_id"]
    assert_equal page_recording.recordable_type, event.metadata["source_recordable_type"]
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
end
