# frozen_string_literal: true

require "test_helper"

class RecordableDeclarationsTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_require_declarations = RecordingStudio.configuration.require_recordable_declarations
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio.configuration.require_recordable_declarations = true
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(RecordingStudioFolder, RecordingStudioPage, RecordingStudioComment, SystemActor)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.require_recordable_declarations = @original_require_declarations
    RecordingStudio::RecordableDeclarations.declarations.replace(@original_declarations)
  end

  def test_recordable_declaration_api_exposes_labels_and_roots
    declaration = RecordingStudio.recordable_declaration_for("Workspace")

    assert declaration
    assert_equal "Workspace", declaration.label
    assert_equal "Workspaces", RecordingStudio.recordable_type_plural_label("Workspace")
    assert RecordingStudio.recordable_declaration_defined?("Workspace")
    assert RecordingStudio.root_recordable_type?("Workspace")
    assert_includes RecordingStudio.root_recordable_types, "Workspace"
    assert_includes RecordingStudio.root_recordable_declarations, declaration
    assert_equal ["Workspace", "RecordingStudioFolder"], RecordingStudio.allowed_parent_types_for("RecordingStudioPage")
  end

  def test_missing_recordable_declarations_raise_by_default
    RecordingStudio.configuration.recordable_types = ["User"]

    assert_raises(RecordingStudio::MissingRecordableDeclaration) do
      RecordingStudio.validate_recordable_declarations!
    end
  end

  def test_missing_recordable_declarations_can_warn_when_requirement_disabled
    RecordingStudio.configuration.recordable_types = ["User"]
    RecordingStudio.configuration.require_recordable_declarations = false

    assert RecordingStudio.validate_recordable_declarations!
    assert RecordingStudio.root_allowed?("User")
  end

  def test_invalid_declarations_raise_even_when_requirement_disabled
    RecordingStudio.configuration.require_recordable_declarations = false

    assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::RecordableDeclarations.register(
        User,
        label: "",
        plural_label: nil,
        root: true,
        options: {}
      )
    end
  end

  def test_record_rejects_new_orphan_recording
    _, root = create_workspace_root

    assert_raises(RecordingStudio::RootNotAllowed) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "Orphan"),
        root_recording: root
      )
    end
  end

  def test_record_rejects_new_recording_under_invalid_parent_type
    _, root = create_workspace_root
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Page"),
      root_recording: root,
      parent_recording: root
    ).recording

    assert_raises(RecordingStudio::InvalidParent) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "Nested page"),
        root_recording: root,
        parent_recording: page
      )
    end
  end

  def test_normal_revisions_do_not_recheck_parent_argument
    _, root = create_workspace_root
    event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Page"),
      root_recording: root,
      parent_recording: root
    )

    revised = RecordingStudioPage.create!(title: "Revision")
    update = RecordingStudio.record!(
      action: "updated",
      recordable: revised,
      recording: event.recording,
      root_recording: root
    )

    assert_equal event.recording, update.recording
  end

  def test_direct_write_model_validation_rejects_invalid_root
    page = RecordingStudioPage.create!(title: "Root page")
    recording = RecordingStudio::Recording.new(recordable: page)

    assert_not recording.valid?
    assert_includes recording.errors[:parent_recording_id].join, "cannot be saved without a parent"
  end

  def test_root_type_without_parent_rules_cannot_be_recorded_under_parent
    declare_system_actor_root_without_parent_rules!
    _, root = create_workspace_root

    assert RecordingStudio::Recording.create!(recordable: SystemActor.create!(name: "Root actor")).root?
    assert_raises(RecordingStudio::InvalidParent) do
      RecordingStudio.record!(
        action: "created",
        recordable: SystemActor.new(name: "Child actor"),
        root_recording: root,
        parent_recording: root
      )
    end
  end

  def test_declaration_parent_rules_are_immutable
    declaration = RecordingStudio.recordable_declaration_for("RecordingStudioPage")

    assert declaration.frozen?
    assert declaration.allowed_parent_types.frozen?
  end

  def test_destroying_parent_with_children_is_restricted_to_prevent_orphans
    _, root = create_workspace_root
    child = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Child"),
      root_recording: root,
      parent_recording: root
    ).recording

    assert_raises(ActiveRecord::DeleteRestrictionError) { root.destroy! }
    assert_not child.reload.orphan?
    assert_equal root.id, child.parent_recording_id
  end

  def test_invalid_parent_record_does_not_persist_recordable
    _, root = create_workspace_root
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Page"),
      root_recording: root,
      parent_recording: root
    ).recording

    assert_no_difference -> { RecordingStudioPage.count } do
      assert_raises(RecordingStudio::InvalidParent) do
        RecordingStudio.record!(
          action: "created",
          recordable: RecordingStudioPage.new(title: "Nested page"),
          root_recording: root,
          parent_recording: page
        )
      end
    end
  end

  private

  def declare_system_actor_root_without_parent_rules!
    RecordingStudio::RecordableDeclarations.register(
      SystemActor,
      label: "System actor",
      plural_label: nil,
      root: true,
      options: {}
    )
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
      SystemActor
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
  end

  def create_workspace_root
    workspace = Workspace.create!(name: "Workspace")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    [workspace, root]
  end
end
