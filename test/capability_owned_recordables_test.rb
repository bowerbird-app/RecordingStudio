# frozen_string_literal: true

require "test_helper"

class CapabilityOwnedRecordablesTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_capabilities = copy_capabilities
    @original_registered_capabilities = copy_registered_capabilities
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup

    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioFolder
      RecordingStudioComment
      SystemActor
    ]
    declare_system_actor_recordable
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(
      Workspace,
      RecordingStudioPage,
      RecordingStudioFolder,
      RecordingStudioComment,
      SystemActor
    )
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.instance_variable_set(:@capabilities, @original_capabilities)
    RecordingStudio.instance_variable_set(:@registered_capabilities, @original_registered_capabilities)
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
    RecordingStudio::DelegatedTypeRegistrar.apply!
  end

  def test_register_capability_accepts_source_child_recordables_and_optional_module
    RecordingStudio.register_capability(
      " actor_tools ",
      nil,
      source: " recording_studio_actor_tools ",
      child_recordables: [SystemActor, "SystemActor"]
    )

    registration = RecordingStudio.registered_capabilities.fetch(:actor_tools)
    assert_nil registration.fetch(:mod)
    assert_equal "recording_studio_actor_tools", registration.fetch(:source)
    assert_equal ["SystemActor"], registration.fetch(:child_recordables)
    assert_equal ["SystemActor"], RecordingStudio.capability_child_recordables_for(:actor_tools)
  end

  def test_register_capability_rejects_invalid_child_metadata
    assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio.register_capability(
        :actor_tools,
        source: "recording_studio_actor_tools",
        child_recordables: [" "]
      )
    end

    assert_raises(ArgumentError) do
      RecordingStudio.register_capability(:actor_tools, recording_methods: Object.new)
    end
  end

  def test_register_capability_is_idempotent_for_same_source_and_rejects_source_conflicts
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["RecordingStudioComment"])

    assert_equal %w[RecordingStudioComment SystemActor],
                 RecordingStudio.capability_child_recordables_for(:actor_tools)

    assert_raises(ArgumentError) do
      RecordingStudio.register_capability(:actor_tools, source: "other_addon", child_recordables: ["SystemActor"])
    end
  end

  def test_capability_registration_alone_does_not_allow_parent
    _, root = create_workspace_root
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])

    assert_not RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)
    assert_equal [], RecordingStudio.capability_allowed_parent_types_for("SystemActor")
  end

  def test_registered_capability_child_is_allowed_under_enabled_parent
    _, root = create_workspace_root
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])
    RecordingStudio.enable_capability(:actor_tools, on: "Workspace")

    assert RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)
    assert RecordingStudio.assert_parent_allowed!(child_type: "SystemActor", parent_recording: root)
    assert_equal ["Workspace"], RecordingStudio.capability_allowed_parent_types_for("SystemActor")
    assert_equal ["Workspace"], RecordingStudio.allowed_parent_types_for("SystemActor")
    assert_equal [], RecordingStudio.declared_allowed_parent_types_for("SystemActor")
  end

  def test_enable_before_registration_applies_child_allowance_after_registration
    _, root = create_workspace_root
    RecordingStudio.enable_capability(:actor_tools, on: "Workspace")

    assert_not RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)

    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])

    assert RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)
  end

  def test_multiple_parent_types_and_sources_accumulate_without_wildcards
    _, root = create_workspace_root
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Page"),
      root_recording: root,
      parent_recording: root
    ).recording
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])
    RecordingStudio.register_capability(:other_actor_tools, source: "other_actor_tools",
                                                           child_recordables: ["SystemActor"])
    RecordingStudio.enable_capability(:actor_tools, on: "Workspace")
    RecordingStudio.enable_capability(:other_actor_tools, on: "RecordingStudioPage")

    assert_equal %w[RecordingStudioPage Workspace], RecordingStudio.allowed_parent_types_for("SystemActor")
    assert RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)
    assert RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: page)
    refute_includes RecordingStudio.allowed_parent_types_for("SystemActor"), "RecordingStudioFolder"
  end

  def test_declaration_and_capability_parent_types_are_unioned
    _, root = create_workspace_root
    RecordingStudio.register_capability(:comment_tools, source: "recording_studio_comment_tools",
                                                        child_recordables: ["RecordingStudioComment"])
    RecordingStudio.enable_capability(:comment_tools, on: "Workspace")

    assert_equal [], RecordingStudio.declared_allowed_parent_types_for("RecordingStudioComment")
    assert_equal %w[RecordingStudioPage Workspace],
                 RecordingStudio.allowed_parent_types_for("RecordingStudioComment")
    assert RecordingStudio.parent_allowed?(child_type: "RecordingStudioComment", parent_recording: root)
  end

  def test_introspection_returns_frozen_copies
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])
    RecordingStudio.enable_capability(:actor_tools, on: "Workspace")

    children = RecordingStudio.capability_child_recordables_for(:actor_tools)
    allowances = RecordingStudio.recordable_parent_allowances_for("SystemActor")

    assert children.frozen?
    assert allowances.frozen?
    assert allowances.fetch("recording_studio_actor_tools").frozen?
    assert_raises(FrozenError) { children << "Other" }
    assert_raises(FrozenError) { allowances["other"] = [] }
    assert_equal ["SystemActor"], RecordingStudio.capability_child_recordables_for(:actor_tools)
  end

  def test_validation_rejects_unregistered_child_and_parent_types
    RecordingStudio.configuration.recordable_types = %w[Workspace SystemActor]
    RecordingStudio.register_capability(:missing_child, source: "missing_child",
                                                        child_recordables: ["RecordingStudioComment"])

    assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio.validate_recordable_declarations!
    end

    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])
    RecordingStudio.enable_capability(:actor_tools, on: "MissingParent")

    assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio.validate_recordable_declarations!
    end
  end

  def test_validation_rejects_root_capability_children
    RecordingStudio::RecordableDeclarations.register(
      SystemActor,
      label: "System actor",
      plural_label: nil,
      root: true,
      options: {}
    )
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])

    assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio.validate_recordable_declarations!
    end
  end

  def test_capability_child_does_not_become_rootable
    actor = SystemActor.create!(name: "Actor")
    RecordingStudio.register_capability(:actor_tools, source: "recording_studio_actor_tools",
                                                     child_recordables: ["SystemActor"])
    RecordingStudio.enable_capability(:actor_tools, on: "Workspace")

    assert_raises(RecordingStudio::RootNotAllowed) { RecordingStudio.root_recording_for(actor) }
  end

  def test_invalid_pending_capability_child_fails_closed_on_write_paths
    _, root = create_workspace_root
    RecordingStudio.register_capability(:missing_child, source: "missing_child", child_recordables: ["MissingChild"])
    RecordingStudio.enable_capability(:missing_child, on: "Workspace")

    assert_not RecordingStudio.parent_allowed?(child_type: "MissingChild", parent_recording: root)
    assert_raises(RecordingStudio::InvalidParent) do
      RecordingStudio.assert_parent_allowed!(child_type: "MissingChild", parent_recording: root)
    end
  end

  private

  def declare_system_actor_recordable
    RecordingStudio::RecordableDeclarations.register(
      SystemActor,
      label: "System actor",
      plural_label: nil,
      root: false,
      options: { allowed_parent_types: [] }
    )
  end

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    root = RecordingStudio.root_recording_for(workspace)
    [workspace, root]
  end

  def copy_capabilities
    capabilities = RecordingStudio.configuration.instance_variable_get(:@capabilities) || {}
    capabilities.transform_values(&:dup)
  end

  def copy_registered_capabilities
    RecordingStudio.registered_capabilities.transform_values do |registration|
      registration.merge(child_recordables: Array(registration[:child_recordables]).dup.freeze)
    end
  end

end
