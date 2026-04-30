# frozen_string_literal: true

require "test_helper"
require "recording_studio/addons/trashable"

class TrashableAddonTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_include_children = RecordingStudio.configuration.include_children

    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioPage]
    RecordingStudio.configuration.include_children = false
    RecordingStudio::DelegatedTypeRegistrar.apply!

    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.include_children = @original_include_children
  end

  def test_trash_and_restore_with_children
    _, root_recording = create_workspace_root
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    root_recording.trash(parent, include_children: true, impersonator: nil)

    assert parent.reload.trashed_at
    assert child.reload.trashed_at

    root_recording.restore(parent, include_children: true, impersonator: nil)

    assert_nil parent.reload.trashed_at
    assert_nil child.reload.trashed_at
  end

  def test_addon_registers_trashable_through_shared_registry
    RecordingStudio::Addons::Trashable.load!

    assert_equal(
      RecordingStudio::Capabilities::Trashable::RecordingMethods,
      RecordingStudio.registered_capabilities.dig(:trashable, :mod)
    )
  end

  def test_hard_delete_removes_recordings
    _, root_recording = create_workspace_root
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    root_recording.hard_delete(parent, include_children: true, impersonator: nil)

    assert_nil RecordingStudio::Recording.including_trashed.find_by(id: parent.id)
    assert_nil RecordingStudio::Recording.including_trashed.find_by(id: child.id)
  end

  def test_trash_mutators_reject_foreign_recording
    _, root_recording = create_workspace_root
    _, other_root = create_workspace_root(name: "Other Workspace")

    foreign_recording = other_root.record(RecordingStudioPage) { |page| page.title = "Foreign" }

    assert_raises(ArgumentError) { root_recording.trash(foreign_recording) }
    assert_raises(ArgumentError) { root_recording.hard_delete(foreign_recording) }
    assert_raises(ArgumentError) { root_recording.restore(foreign_recording) }
  end

  def test_trash_uses_configuration_include_children
    _, root_recording = create_workspace_root
    RecordingStudio.configuration.include_children = true

    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    root_recording.trash(parent, impersonator: nil)

    assert parent.reload.trashed_at
    assert child.reload.trashed_at
  end

  def test_trash_restore_and_hard_delete_ignore_nil
    _, root_recording = create_workspace_root

    assert_nil root_recording.trash(nil, impersonator: nil)
    assert_nil root_recording.restore(nil, impersonator: nil)
    assert_nil root_recording.hard_delete(nil, impersonator: nil)
    assert_equal 0, RecordingStudio::Event.count
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    [workspace, root_recording]
  end
end
