# frozen_string_literal: true

require "test_helper"

class CapabilitiesTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_feature_flags = RecordingStudio.features.to_h
    RecordingStudio.features.copyable = true
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioFolder
      RecordingStudioComment
      RecordingStudio::Access
      RecordingStudio::AccessBoundary
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    RecordingStudio.apply_capabilities!

    RecordingStudio::Event.delete_all
    RecordingStudio::DeviceSession.delete_all
    RecordingStudio::Recording.delete_all
    RecordingStudio::Access.delete_all
    RecordingStudio::AccessBoundary.delete_all
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

  def test_copy_to_raises_when_copyable_feature_is_disabled
    _, root = create_workspace_root
    actor = create_user("copy-disabled@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)
    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "A"
    end
    target_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "B"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end

    RecordingStudio.features.copyable = false

    error = assert_raises(RecordingStudio::CapabilityDisabled) do
      page_recording.copy_to!(new_parent: target_parent, actor: actor)
    end
    assert_equal "Legacy copyable feature is disabled", error.message
  end

  def test_copy_to_denies_when_actor_lacks_source_view_access
    _, root = create_workspace_root
    actor = create_user("copy-source-deny@example.com")

    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    target_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Target"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end
    grant_access(recording: target_parent, actor: actor, role: :edit)

    error = assert_raises(RecordingStudio::AccessDenied) do
      page_recording.copy_to!(new_parent: target_parent, actor: actor)
    end
    assert_equal "Actor does not have view access on the source recording", error.message
  end

  def test_copy_to_denies_when_actor_lacks_target_edit_access
    _, root = create_workspace_root
    actor = create_user("copy-target-deny@example.com")

    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    target_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Target"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end
    grant_access(recording: page_recording, actor: actor, role: :view)

    error = assert_raises(RecordingStudio::AccessDenied) do
      page_recording.copy_to!(new_parent: target_parent, actor: actor)
    end
    assert_equal "Actor does not have edit access on the target recording", error.message
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

  def test_duplicate_creates_sibling_recording_and_logs_provenance
    _, root = create_workspace_root
    actor = create_user("duplicator@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Parent"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: parent) do |page|
      page.title = "Duplicate me"
    end

    assert page_recording.duplicatable?(actor: actor)

    duplicated = page_recording.duplicate!(actor: actor, metadata: { reason: "template" })

    assert_equal parent.id, duplicated.parent_recording_id
    assert_equal root.id, duplicated.root_recording_id
    assert_equal "Duplicate me", duplicated.recordable.title
    assert_not_equal page_recording.id, duplicated.id
    assert_not_equal page_recording.recordable_id, duplicated.recordable_id

    event = duplicated.events.first
    assert_equal "duplicated", event.action
    assert_equal "template", event.metadata["reason"]
    assert_equal page_recording.id, event.metadata["source_recording_id"]
    assert_equal page_recording.recordable_id, event.metadata["source_recordable_id"]
    assert_equal page_recording.recordable_type, event.metadata["source_recordable_type"]
    assert_equal parent.id, event.metadata["source_parent_recording_id"]
  end

  def test_duplicate_with_children_preserves_subtree_structure
    _, root = create_workspace_root
    actor = create_user("duplicate-tree@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Projects"
    end
    source = root.record(RecordingStudioFolder, actor: actor, parent_recording: parent) do |folder|
      folder.name = "Source Folder"
    end
    child_folder = root.record(RecordingStudioFolder, actor: actor, parent_recording: source) do |folder|
      folder.name = "Nested Folder"
    end
    nested_page = root.record(RecordingStudioPage, actor: actor, parent_recording: child_folder) do |page|
      page.title = "Nested Page"
    end

    duplicated = source.duplicate!(actor: actor, include_children: true)

    duplicated_child_folder = duplicated.child_recordings.find_by!(recordable_type: "RecordingStudioFolder")
    duplicated_nested_page = duplicated_child_folder.child_recordings.find_by!(recordable_type: "RecordingStudioPage")

    assert_equal parent.id, duplicated.parent_recording_id
    assert_equal "Source Folder", duplicated.recordable.name
    assert_equal "Nested Folder", duplicated_child_folder.recordable.name
    assert_equal "Nested Page", duplicated_nested_page.recordable.title
    assert_not_equal child_folder.id, duplicated_child_folder.id
    assert_not_equal nested_page.id, duplicated_nested_page.id
    assert_equal duplicated.id, duplicated_child_folder.parent_recording_id
    assert_equal duplicated_child_folder.id, duplicated_nested_page.parent_recording_id
  end

  def test_duplicate_uses_idempotency_key_for_safe_retries
    _, root = create_workspace_root
    actor = create_user("duplicate-idempotent@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Parent"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: parent) do |page|
      page.title = "Retry me"
    end

    first = page_recording.duplicate!(actor: actor, idempotency_key: "dup-123")
    second = page_recording.duplicate!(actor: actor, idempotency_key: "dup-123")

    assert_equal first.id, second.id
    assert_equal 1, RecordingStudio::Event.where(action: "duplicated", idempotency_key: "dup-123").count
  end

  def test_duplicate_rejects_trashed_source_recordings
    _, root = create_workspace_root
    actor = create_user("duplicate-trashed@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: root) do |page|
      page.title = "Trash me"
    end
    root.trash(page_recording, actor: actor)

    error = assert_raises(ArgumentError) do
      page_recording.duplicate!(actor: actor)
    end

    assert_equal "trashed recordings cannot be duplicated", error.message
  end

  def test_duplicate_include_children_requires_opt_in_for_all_descendants
    _, root = create_workspace_root
    actor = create_user("duplicate-opt-in@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: root) do |page|
      page.title = "Discuss"
    end
    page_recording.comment!(body: "This comment should block duplication", actor: actor)

    error = assert_raises(RecordingStudio::CapabilityDisabled) do
      page_recording.duplicate!(actor: actor, include_children: true)
    end

    assert_match(/Capability :duplicable is not enabled for RecordingStudioComment/, error.message)
  end

  def test_duplicate_include_children_rejects_access_boundary_recordings
    _, root = create_workspace_root
    actor = create_user("duplicate-boundary@example.com")
    grant_root_access(root: root, actor: actor, role: :admin)

    folder_recording = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Boundary parent"
    end
    root.record(RecordingStudio::AccessBoundary, actor: actor, parent_recording: folder_recording) do |boundary|
      boundary.minimum_role = :admin
    end

    error = assert_raises(RecordingStudio::CapabilityDisabled) do
      folder_recording.duplicate!(actor: actor, include_children: true)
    end

    assert_match(/Capability :duplicable is not enabled for RecordingStudio::AccessBoundary/, error.message)
  end

  def test_duplicate_raises_when_idempotency_mode_is_raise_and_key_is_reused
    _, root = create_workspace_root
    actor = create_user("duplicate-idempotency-raise@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Parent"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: parent) do |page|
      page.title = "Raise on retry"
    end

    original_mode = RecordingStudio.configuration.idempotency_mode
    RecordingStudio.configuration.idempotency_mode = :raise

    page_recording.duplicate!(actor: actor, idempotency_key: "dup-raise")

    assert_raises(RecordingStudio::IdempotencyError) do
      page_recording.duplicate!(actor: actor, idempotency_key: "dup-raise")
    end
  ensure
    RecordingStudio.configuration.idempotency_mode = original_mode
  end

  def test_root_recordings_are_not_duplicatable
    _, root = create_workspace_root
    actor = create_user("duplicate-root@example.com")

    refute root.duplicatable?(actor: actor)

    error = assert_raises(ArgumentError) do
      root.duplicate!(actor: actor)
    end

    assert_equal "root recordings cannot be duplicated", error.message
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
