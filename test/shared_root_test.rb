# frozen_string_literal: true

require "test_helper"

class SharedRootTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_require_declarations = RecordingStudio.configuration.require_recordable_declarations
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    @original_registered_capabilities = RecordingStudio.registered_capabilities.transform_values(&:dup)
    @original_capabilities = RecordingStudio.configuration.instance_variable_get(:@capabilities).transform_values(&:dup)
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
      SystemActor
    ]
    RecordingStudio.configuration.require_recordable_declarations = true
    declare_system_actor_capability_child!
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(
      RecordingStudioFolder,
      RecordingStudioPage,
      RecordingStudioComment,
      SystemActor
    )
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.require_recordable_declarations = @original_require_declarations
    RecordingStudio.instance_variable_set(:@registered_capabilities, @original_registered_capabilities)
    RecordingStudio.configuration.instance_variable_set(:@capabilities, @original_capabilities)
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
    RecordingStudio::DelegatedTypeRegistrar.apply!
  end

  def test_omitted_shared_flag_defaults_to_false
    declaration = RecordingStudio.recordable_declaration_for("Workspace")

    assert_not declaration.shared?
    assert_not RecordingStudio.shared_root_type?("Workspace")
  end

  def test_shared_true_requires_root_true
    error = assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::RecordableDeclarations.register(
        RecordingStudioPage,
        label: "Page",
        plural_label: nil,
        root: false,
        options: { shared: true, allowed_parent_types: ["Workspace"] }
      )
    end

    assert_match(/shared: true requires root: true/, error.message)
  end

  def test_shared_must_be_boolean
    error = assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::RecordableDeclarations.register(
        Workspace,
        label: "Workspace",
        plural_label: "Workspaces",
        root: true,
        options: { shared: "yes" }
      )
    end

    assert_match(/shared must be true or false/, error.message)
  end

  def test_shared_root_cannot_declare_non_empty_allowed_parent_types
    error = assert_raises(RecordingStudio::InvalidRecordableDeclaration) do
      RecordingStudio::RecordableDeclarations.register(
        Workspace,
        label: "Workspace",
        plural_label: "Workspaces",
        root: true,
        options: { shared: true, allowed_parent_types: ["RecordingStudioPage"] }
      )
    end

    assert_match(/shared: true cannot declare allowed_parent_types/, error.message)
  end

  def test_shared_root_may_declare_empty_allowed_parent_types
    declaration = declare_shared_workspace!

    assert declaration.shared?
    assert declaration.root?
    assert_equal [], declaration.allowed_parent_types
  end

  def test_shared_root_helpers_list_shared_types_and_recordings
    declare_shared_workspace!
    workspace, root = create_workspace_root
    page = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Group"),
      root_recording: root,
      parent_recording: root
    ).recording

    assert_equal ["Workspace"], RecordingStudio.shared_root_types
    assert_includes RecordingStudio.shared_root_declarations, RecordingStudio.recordable_declaration_for("Workspace")
    assert RecordingStudio.shared_root_type?(workspace)
    assert RecordingStudio.shared_root?(root)
    assert root.shared_root?
    assert_not RecordingStudio.shared_root?(page)
    assert_not page.shared_root?
    assert RecordingStudio.shared_root_tree?(root)
    assert RecordingStudio.shared_root_tree?(page)
    assert page.shared_root_tree?
  end

  def test_root_recording_for_still_creates_shared_roots
    declare_shared_workspace!
    workspace = Workspace.create!(name: "Messages")

    root = RecordingStudio.root_recording_for(workspace)

    assert_predicate root, :persisted?
    assert root.root?
    assert root.shared_root?
    assert_equal workspace, root.recordable
  end

  def test_domain_children_can_be_recorded_under_a_shared_root
    declare_shared_workspace!
    _, root = create_workspace_root

    page = root.record(RecordingStudioPage) { |recordable| recordable.title = "Message group" }

    assert_equal root, page.parent_recording
    assert_equal root.id, page.root_recording_id
    assert page.shared_root_tree?
  end

  def test_capability_owned_children_cannot_use_a_shared_root_as_direct_parent
    declare_shared_workspace!
    _, root = create_workspace_root
    RecordingStudio.register_capability(
      :actor_tools,
      source: "recording_studio_actor_tools",
      child_recordables: ["SystemActor"]
    )
    RecordingStudio.enable_capability(:actor_tools, on: "Workspace")

    assert_not RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)
    assert_equal [], RecordingStudio.capability_parent_types_for("SystemActor")
    assert_equal [], RecordingStudio.allowed_parent_types_for("SystemActor")
    assert_equal [], RecordingStudio.child_recordable_types_for("Workspace")
    assert_equal [], RecordingStudio.parent_capabilities_for(child_type: "SystemActor", parent_recording: root)
    assert_equal({ "recording_studio_actor_tools" => [] },
                 RecordingStudio.recordable_parent_allowances_for("SystemActor"))

    assert_raises(RecordingStudio::InvalidParent) do
      RecordingStudio.record!(
        action: "created",
        recordable: SystemActor.new(name: "Grant"),
        root_recording: root,
        parent_recording: root
      )
    end
  end

  def test_capability_owned_children_cannot_bypass_shared_root_via_allowed_parent_types
    declare_shared_workspace!
    _, root = create_workspace_root
    RecordingStudio::RecordableDeclarations.register(
      SystemActor,
      label: "System actor",
      plural_label: nil,
      root: false,
      options: { allowed_parent_types: ["Workspace"] }
    )
    RecordingStudio.register_capability(
      :actor_tools,
      source: "recording_studio_actor_tools",
      child_recordables: ["SystemActor"]
    )
    RecordingStudio.enable_capability(:actor_tools, on: "Workspace")

    assert_not RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: root)
    assert_equal [], RecordingStudio.allowed_parent_types_for("SystemActor")
    assert_raises(RecordingStudio::InvalidParent) do
      RecordingStudio.record!(
        action: "created",
        recordable: SystemActor.new(name: "Grant"),
        root_recording: root,
        parent_recording: root
      )
    end
  end

  def test_capability_owned_children_remain_allowed_under_descendants_of_a_shared_root
    declare_shared_workspace!
    _, root = create_workspace_root
    page = root.record(RecordingStudioPage) { |recordable| recordable.title = "Message group" }
    RecordingStudio.register_capability(
      :actor_tools,
      source: "recording_studio_actor_tools",
      child_recordables: ["SystemActor"]
    )
    RecordingStudio.enable_capability(:actor_tools, on: "RecordingStudioPage")

    assert RecordingStudio.parent_allowed?(child_type: "SystemActor", parent_recording: page)
    assert_equal ["RecordingStudioPage"], RecordingStudio.capability_parent_types_for("SystemActor")
    assert_equal ["RecordingStudioPage"], RecordingStudio.allowed_parent_types_for("SystemActor")
    assert_includes RecordingStudio.child_recordable_types_for("RecordingStudioPage"), "SystemActor"
    assert_equal [:actor_tools],
                 RecordingStudio.parent_capabilities_for(child_type: "SystemActor", parent_recording: page)

    child = RecordingStudio.record!(
      action: "created",
      recordable: SystemActor.new(name: "Member"),
      root_recording: root,
      parent_recording: page
    ).recording

    assert_equal page, child.parent_recording
    assert child.shared_root_tree?
    assert_not child.shared_root?
  end

  def test_shared_root_predicates_are_false_for_nil_and_owned_trees
    _, root = create_workspace_root
    page = root.record(RecordingStudioPage) { |recordable| recordable.title = "Owned page" }

    assert_not RecordingStudio.shared_root?(nil)
    assert_not RecordingStudio.shared_root_tree?(nil)
    assert_not RecordingStudio.shared_root?(root)
    assert_not RecordingStudio.shared_root_tree?(page)
    assert_not root.shared_root?
    assert_not page.shared_root_tree?
  end

  private

  def declare_shared_workspace!
    RecordingStudio::RecordableDeclarations.register(
      Workspace,
      label: "Workspace",
      plural_label: "Workspaces",
      root: true,
      options: { shared: true, allowed_parent_types: [] }
    )
    RecordingStudio.recordable_declaration_for("Workspace")
  end

  def declare_system_actor_capability_child!
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
end
