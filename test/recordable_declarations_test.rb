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
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
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
    assert_equal [], RecordingStudio.declared_parent_types_for("RecordingStudioComment")
    assert_equal ["RecordingStudioPage"], RecordingStudio.capability_parent_types_for("RecordingStudioComment")
    assert_equal %w[Workspace RecordingStudioFolder RecordingStudioPage],
                 RecordingStudio.allowed_parent_types_for("RecordingStudioPage")
    assert_equal ["RecordingStudioPage"], RecordingStudio.allowed_parent_types_for("RecordingStudioComment")
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

  def test_legacy_missing_declaration_fallback_rejects_unregistered_types
    _, root = create_workspace_root
    RecordingStudio.configuration.require_recordable_declarations = false

    assert_not RecordingStudio.root_allowed?("SystemActor")
    assert_not RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)

    assert_raises(RecordingStudio::RootNotAllowed) do
      RecordingStudio.record!(
        action: "created",
        recordable: SystemActor.new(name: "Unregistered actor"),
        root_recording: root
      )
    end
  end

  def test_declarations_accessor_returns_read_only_copy
    declarations = RecordingStudio::RecordableDeclarations.declarations

    assert declarations.frozen?
    assert_raises(FrozenError) { declarations.delete("Workspace") }
    assert RecordingStudio.recordable_declaration_defined?("Workspace")
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

  def test_validation_requires_non_root_recordables_to_have_declared_or_capability_parent_types
    RecordingStudio::RecordableDeclarations.register(
      SystemActor,
      label: "System actor",
      plural_label: nil,
      root: false,
      options: {}
    )
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
      SystemActor
    ]
    error = assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::DelegatedTypeRegistrar.apply!
      RecordingStudio.validate_recordable_declarations!
    end

    assert_match(/SystemActor: allowed_parent_types is required when root is false/, error.message)
  end

  def test_record_rejects_new_orphan_recording
    _, root = create_workspace_root

    error = assert_raises(RecordingStudio::RootNotAllowed) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "Orphan"),
        root_recording: root
      )
    end

    assert_equal "parent_recording_id is required for RecordingStudioPage", error.message
  end

  def test_record_rejects_new_recording_under_invalid_parent_type
    _, root = create_workspace_root

    assert_raises(RecordingStudio::InvalidParent) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioComment.new(body: "Comment"),
        root_recording: root,
        parent_recording: root
      )
    end
  end

  def test_record_rechecks_persisted_parent_root_before_creating_child
    _, root = create_workspace_root
    _, other_root = create_workspace_root
    foreign_parent = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Foreign parent"),
      root_recording: other_root,
      parent_recording: other_root
    ).recording
    foreign_parent.root_recording_id = root.id

    assert_raises(ArgumentError) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "Boundary bypass"),
        root_recording: root,
        parent_recording: foreign_parent
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
    assert_includes recording.errors[:parent_recording_id], "is required for RecordingStudioPage"
  end

  def test_root_recording_predicate_rejects_structural_roots_without_root_declaration
    page = RecordingStudioPage.create!(title: "Root page")
    recording = RecordingStudio::Recording.new(recordable: page)
    recording.id = SecureRandom.uuid
    recording.root_recording_id = recording.id
    recording.save!(validate: false)

    assert_not RecordingStudio.root_recording?(recording)
    assert_not recording.root?
    assert_raises(ArgumentError) { RecordingStudio.assert_root_recording!(recording) }
  end

  def test_root_type_without_parent_rules_cannot_be_recorded_under_parent
    declare_system_actor_root_without_parent_rules!
    _, root = create_workspace_root

    assert RecordingStudio.root_recording_for(SystemActor.create!(name: "Root actor")).root?
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

    assert_raises(ActiveRecord::RecordNotDestroyed) { root.destroy! }
    assert_not child.reload.orphan?
    assert_equal root.id, child.parent_recording_id
  end

  def test_root_recording_for_rejects_non_root_recordable
    page = RecordingStudioPage.create!(title: "Root page")

    assert_raises(RecordingStudio::RootNotAllowed) do
      RecordingStudio.root_recording_for(page)
    end
  end

  def test_comment_can_be_recorded_under_page
    _, root = create_workspace_root
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Page"),
      root_recording: root,
      parent_recording: root
    ).recording

    comment = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioComment.new(body: "Comment"),
      root_recording: root,
      parent_recording: page
    ).recording

    assert_equal page, comment.parent_recording
  end

  def test_capability_parent_introspection_lists_parent_sources_and_capabilities
    _, root = create_workspace_root
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Page"),
      root_recording: root,
      parent_recording: root
    ).recording

    assert_equal ["RecordingStudioComment"], RecordingStudio.child_recordable_types_for("RecordingStudioPage")
    assert_equal [:commentable],
                 RecordingStudio.parent_capabilities_for(
                   child_type: "RecordingStudioComment",
                   parent_recording: page
                 )
    assert_equal({ "Capabilities::Commentable" => ["RecordingStudioPage"] },
                 RecordingStudio.recordable_parent_allowances_for("RecordingStudioComment"))
  end

  def test_comment_cannot_be_recorded_under_root
    _, root = create_workspace_root

    assert_raises(RecordingStudio::InvalidParent) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioComment.new(body: "Comment"),
        root_recording: root,
        parent_recording: root
      )
    end
  end

  def test_record_bang_rejects_root_recordable_without_parent_under_existing_root
    _, root = create_workspace_root

    assert_raises(RecordingStudio::OrphanRecording) do
      RecordingStudio.record!(
        action: "created",
        recordable: Workspace.new(name: "Other root"),
        root_recording: root
      )
    end
  end

  def test_direct_write_rejects_parentless_recording_under_existing_root
    _, root = create_workspace_root
    recording = RecordingStudio::Recording.new(
      root_recording: root,
      recordable: Workspace.create!(name: "Other root")
    )

    assert_not recording.valid?
    assert_includes recording.errors[:parent_recording_id].join, "cannot be blank"
  end

  def test_invalid_parent_record_does_not_persist_recordable
    _, root = create_workspace_root

    assert_no_difference -> { RecordingStudioComment.count } do
      assert_raises(RecordingStudio::InvalidParent) do
        RecordingStudio.record!(
          action: "created",
          recordable: RecordingStudioComment.new(body: "Comment"),
          root_recording: root,
          parent_recording: root
        )
      end
    end
  end

  def test_invalid_convenience_record_does_not_persist_recordable
    _, root = create_workspace_root

    assert_no_difference -> { RecordingStudioComment.count } do
      assert_raises(RecordingStudio::InvalidParent) do
        root.record(RecordingStudioComment) do |recordable|
          recordable.body = "Comment"
        end
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
    root = RecordingStudio.root_recording_for(workspace)
    [workspace, root]
  end
end
