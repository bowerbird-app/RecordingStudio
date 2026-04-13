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

  def test_page_copy_creates_duplicate_in_place_and_logs_source_metadata
    _, root = create_workspace_root
    actor = create_user("copier@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end

    result = page_recording.copy!(actor: actor, metadata: { reason: "template" })
    copied = result.recording

    assert_equal "Copy me", copied.recordable.title
    assert_equal source_parent.id, copied.parent_recording_id
    assert_not_equal page_recording.recordable_id, copied.recordable_id
    assert_nil result.redirect
    event = copied.events.first
    assert_equal "copied", event.action
    assert_equal page_recording.id, event.metadata["source_recording_id"]
    assert_equal page_recording.recordable_id, event.metadata["source_recordable_id"]
    assert_equal page_recording.recordable_type, event.metadata["source_recordable_type"]
  end

  def test_copy_returns_redirect_instructions
    _, root = create_workspace_root
    actor = create_user("copy-redirects@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)
    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end

    reload_result = page_recording.copy!(actor: actor, redirect: :reload)
    open_result = page_recording.copy!(actor: actor, redirect: :open)
    return_to_result = page_recording.copy!(
      actor: actor,
      redirect: :return_to,
      return_to: "https://example.com/recordings/#{page_recording.id}?copied=1"
    )
    invalid_return_to_result = page_recording.copy!(actor: actor, redirect: :return_to, return_to: "%zz")
    protocol_relative_result = page_recording.copy!(actor: actor, redirect: :return_to, return_to: "//evil.test/path")
    path_traversal_result = page_recording.copy!(actor: actor, redirect: :return_to, return_to: "/../admin")
    encoded_path_traversal_result = page_recording.copy!(
      actor: actor,
      redirect: :return_to,
      return_to: "/%2e%2e/admin"
    )
    fragment_result = page_recording.copy!(
      actor: actor,
      redirect: :return_to,
      return_to: "https://example.com/recordings/#{page_recording.id}?copied=1#details"
    )
    nested_query_result = page_recording.copy!(
      actor: actor,
      redirect: :return_to,
      return_to: "/recordings/#{page_recording.id}?filters%5Bcopied%5D=1&filters%5Bids%5D%5B%5D=2"
    )

    assert_equal :reload, reload_result.redirect.action
    assert_equal :open, open_result.redirect.action
    assert_equal open_result.recording, open_result.redirect.recording
    assert_equal :return_to, return_to_result.redirect.action
    assert_equal "/recordings/#{page_recording.id}?copied=1", return_to_result.redirect.location
    assert_equal "/recordings/#{page_recording.id}?copied=1", fragment_result.redirect.location
    assert_equal "/recordings/#{page_recording.id}?filters%5Bcopied%5D=1&filters%5Bids%5D%5B%5D=2",
                 nested_query_result.redirect.location
    assert_nil invalid_return_to_result.redirect
    assert_nil protocol_relative_result.redirect
    assert_nil path_traversal_result.redirect
    assert_nil encoded_path_traversal_result.redirect
  end

  def test_folder_copy_uses_class_level_deep_copy_defaults
    _, root = create_workspace_root
    actor = create_user("deep-copy@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    source_folder = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    source_page = root.record(RecordingStudioPage, actor: actor, parent_recording: source_folder) do |page|
      page.title = "Child Page"
    end
    nested_folder = root.record(RecordingStudioFolder, actor: actor, parent_recording: source_folder) do |folder|
      folder.name = "Nested"
    end
    root.record(RecordingStudioPage, actor: actor, parent_recording: nested_folder) do |page|
      page.title = "Nested Page"
    end

    result = source_folder.copy!(actor: actor)
    copied_folder = result.recording
    copied_page = copied_folder.child_recordings.of_type("RecordingStudioPage").sole
    copied_nested_folder = copied_folder.child_recordings.of_type("RecordingStudioFolder").sole

    assert_equal source_folder.parent_recording_id, copied_folder.parent_recording_id
    assert_equal source_page.recordable.title, copied_page.recordable.title
    assert_equal copied_folder.id, copied_page.parent_recording_id
    assert_equal nested_folder.recordable.name, copied_nested_folder.recordable.name
    assert_equal copied_folder.id, copied_nested_folder.parent_recording_id
    assert_equal "Nested Page",
                 copied_nested_folder.child_recordings.of_type("RecordingStudioPage").sole.recordable.title
  end

  def test_folder_copy_skips_sensitive_recordables_unless_explicitly_allowed
    _, root = create_workspace_root
    actor = create_user("deep-copy-sensitive@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    source_folder = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    root.record(RecordingStudioPage, actor: actor, parent_recording: source_folder) do |page|
      page.title = "Child Page"
    end
    grant_access(recording: source_folder, actor: actor, role: :admin)

    copied_folder = source_folder.copy!(actor: actor, deep_copy: true).recording

    assert_equal ["RecordingStudioPage"], copied_folder.child_recordings.pluck(:recordable_type)
  end

  def test_folder_copy_allows_per_call_deep_copy_filters
    _, root = create_workspace_root
    actor = create_user("deep-copy-filter@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    source_folder = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    root.record(RecordingStudioPage, actor: actor, parent_recording: source_folder) do |page|
      page.title = "Child Page"
    end
    root.record(RecordingStudioFolder, actor: actor, parent_recording: source_folder) do |folder|
      folder.name = "Nested"
    end

    result = source_folder.copy!(actor: actor, deep_copy: { include: ["RecordingStudioFolder"] })
    copied_folder = result.recording

    assert_equal ["RecordingStudioFolder"], copied_folder.child_recordings.pluck(:recordable_type)
  end

  def test_copy_emits_event_notifications_through_existing_instrumentation
    _, root = create_workspace_root
    actor = create_user("copy-notifications@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)
    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end
    events = []

    subscriber = ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    copied = page_recording.copy!(actor: actor).recording

    assert_equal "copied", events.last.payload[:action]
    assert_equal copied.id, events.last.payload[:recording_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_copy_raises_when_copyable_feature_is_disabled
    _, root = create_workspace_root
    actor = create_user("copy-disabled@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)
    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "A"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end

    RecordingStudio.features.copyable = false

    error = assert_raises(RecordingStudio::CapabilityDisabled) do
      page_recording.copy!(actor: actor)
    end
    assert_equal "Legacy copyable feature is disabled", error.message
  end

  def test_copy_allows_when_actor_can_edit_source_parent
    _, root = create_workspace_root
    owner = create_user("copy-source-owner@example.com")
    actor = create_user("copy-source-editor@example.com")
    grant_root_access(root: root, actor: owner, role: :edit)

    source_parent = root.record(RecordingStudioFolder, actor: owner, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    page_recording = root.record(RecordingStudioPage, actor: owner, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end
    grant_access(recording: source_parent, actor: actor, role: :edit)

    copied = page_recording.copy!(actor: actor).recording

    assert_equal source_parent.id, copied.parent_recording_id
    assert_equal "Copy me", copied.recordable.title
  end

  def test_copy_denies_when_actor_lacks_copy_parent_edit_access
    _, root = create_workspace_root
    actor = create_user("copy-target-deny@example.com")

    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end
    grant_access(recording: page_recording, actor: actor, role: :view)

    error = assert_raises(RecordingStudio::AccessDenied) do
      page_recording.copy!(actor: actor)
    end
    assert_equal "Actor does not have edit access on the copy parent", error.message
  end

  def test_recordings_expose_copy_but_not_copy_to
    _, root = create_workspace_root
    actor = create_user("copy-transition@example.com")
    grant_root_access(root: root, actor: actor, role: :edit)

    source_parent = root.record(RecordingStudioFolder, actor: actor, parent_recording: root) do |folder|
      folder.name = "Source"
    end
    page_recording = root.record(RecordingStudioPage, actor: actor, parent_recording: source_parent) do |page|
      page.title = "Copy me"
    end

    assert_respond_to page_recording, :copy!
    refute_respond_to page_recording, :copy_to!
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
