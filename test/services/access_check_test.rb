# frozen_string_literal: true

require "test_helper"

class AccessCheckTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[
      RecordingStudioPage RecordingStudioComment
      RecordingStudio::Access RecordingStudio::AccessBoundary
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.unscoped.delete_all
    RecordingStudio::Access.delete_all
    RecordingStudio::AccessBoundary.delete_all
    RecordingStudioPage.delete_all
    RecordingStudioComment.delete_all
    Workspace.delete_all
    User.delete_all

    @workspace = Workspace.create!(name: "Test Workspace")
    @actor = User.create!(name: "Alice", email: "alice@example.com", password: "password123")
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  # --- Role hierarchy ---

  def test_admin_satisfies_edit_and_view
    page_recording = create_page_recording("Page")
    grant_access(page_recording, @actor, :admin)

    assert AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :admin)
    assert AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :edit)
    assert AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :view)
  end

  def test_edit_satisfies_view_but_not_admin
    page_recording = create_page_recording("Page")
    grant_access(page_recording, @actor, :edit)

    assert AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :edit)
    assert AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :view)
    refute AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :admin)
  end

  def test_view_satisfies_only_view
    page_recording = create_page_recording("Page")
    grant_access(page_recording, @actor, :view)

    assert AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :view)
    refute AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :edit)
    refute AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :admin)
  end

  # --- Direct access on recording ---

  def test_direct_access_on_recording
    page_recording = create_page_recording("Page")
    grant_access(page_recording, @actor, :edit)

    assert_equal :edit, AccessCheck.role_for(actor: @actor, recording: page_recording)
  end

  def test_no_access_returns_nil
    page_recording = create_page_recording("Page")

    assert_nil AccessCheck.role_for(actor: @actor, recording: page_recording)
    refute AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :view)
  end

  # --- Access inherited from parent recording ---

  def test_access_inherited_from_parent
    parent_recording = create_page_recording("Parent")
    child_recording = create_child_recording(parent_recording, "Child")

    grant_access(parent_recording, @actor, :admin)

    assert_equal :admin, AccessCheck.role_for(actor: @actor, recording: child_recording)
  end

  def test_access_inherited_from_grandparent
    grandparent = create_page_recording("Grandparent")
    parent = create_child_recording(grandparent, "Parent")
    child = create_child_recording(parent, "Child")

    grant_access(grandparent, @actor, :edit)

    assert_equal :edit, AccessCheck.role_for(actor: @actor, recording: child)
  end

  # --- Access via container-level access ---

  def test_container_level_access
    page_recording = create_page_recording("Page")
    grant_container_access(@workspace, @actor, :view)

    assert_equal :view, AccessCheck.role_for(actor: @actor, recording: page_recording)
  end

  def test_container_level_access_satisfies_role_check
    page_recording = create_page_recording("Page")
    grant_container_access(@workspace, @actor, :admin)

    assert AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :edit)
  end

  def test_containers_for_returns_only_containers_with_root_access
    other_workspace = Workspace.create!(name: "Other Workspace")

    grant_container_access(@workspace, @actor, :view)

    other_page = RecordingStudioPage.create!(title: "Other Page")
    other_page_recording = RecordingStudio::Recording.create!(container: other_workspace, recordable: other_page)
    other_access = RecordingStudio::Access.create!(actor: @actor, role: :admin)
    RecordingStudio::Recording.create!(container: other_workspace, recordable: other_access,
                                       parent_recording: other_page_recording)

    containers = AccessCheck.containers_for(actor: @actor)
    assert_includes containers, [@workspace.class.name, @workspace.id]
    refute_includes containers, [other_workspace.class.name, other_workspace.id]
  end

  def test_containers_for_supports_minimum_role
    other_workspace = Workspace.create!(name: "Other Workspace")

    grant_container_access(@workspace, @actor, :view)
    grant_container_access(other_workspace, @actor, :admin)

    containers = AccessCheck.containers_for(actor: @actor, minimum_role: :edit)
    refute_includes containers, [@workspace.class.name, @workspace.id]
    assert_includes containers, [other_workspace.class.name, other_workspace.id]
  end

  # --- AccessBoundary stops inheritance ---

  def test_boundary_stops_inheritance
    parent = create_page_recording("Parent")
    boundary_recording = create_boundary_child(parent)
    child = create_child_recording(boundary_recording, "Child")

    # Access granted above boundary
    grant_access(parent, @actor, :admin)

    # No access inside boundary
    assert_nil AccessCheck.role_for(actor: @actor, recording: child)
  end

  def test_boundary_allows_explicit_access_inside
    parent = create_page_recording("Parent")
    boundary_recording = create_boundary_child(parent)
    child = create_child_recording(boundary_recording, "Child")

    grant_access(child, @actor, :edit)

    assert_equal :edit, AccessCheck.role_for(actor: @actor, recording: child)
  end

  def test_boundary_allows_access_on_boundary_itself
    parent = create_page_recording("Parent")
    boundary_recording = create_boundary_child(parent)

    grant_access(boundary_recording, @actor, :view)

    assert_equal :view, AccessCheck.role_for(actor: @actor, recording: boundary_recording)
  end

  # --- AccessBoundary with minimum_role allows passthrough ---

  def test_boundary_with_minimum_role_allows_passthrough
    parent = create_page_recording("Parent")
    boundary_recording = create_boundary_child(parent, minimum_role: :edit)
    child = create_child_recording(boundary_recording, "Child")

    # Access above boundary with admin role (>= edit minimum_role)
    grant_access(parent, @actor, :admin)

    assert_equal :admin, AccessCheck.role_for(actor: @actor, recording: child)
  end

  def test_boundary_with_minimum_role_blocks_insufficient_role
    parent = create_page_recording("Parent")
    boundary_recording = create_boundary_child(parent, minimum_role: :admin)
    child = create_child_recording(boundary_recording, "Child")

    # Access above boundary with edit role (< admin minimum_role)
    grant_access(parent, @actor, :edit)

    assert_nil AccessCheck.role_for(actor: @actor, recording: child)
  end

  def test_boundary_with_minimum_role_allows_container_passthrough
    parent = create_page_recording("Parent")
    boundary_recording = create_boundary_child(parent, minimum_role: :view)
    child = create_child_recording(boundary_recording, "Child")

    # Container-level access with view role (>= view minimum_role)
    grant_container_access(@workspace, @actor, :view)

    assert_equal :view, AccessCheck.role_for(actor: @actor, recording: child)
  end

  # --- Boundary at root blocks container access ---

  def test_boundary_at_root_blocks_container_access_without_minimum_role
    boundary_recording = create_boundary_root
    child = create_child_recording(boundary_recording, "Child")

    grant_container_access(@workspace, @actor, :admin)

    assert_nil AccessCheck.role_for(actor: @actor, recording: child)
  end

  def test_boundary_at_root_allows_container_access_with_minimum_role
    boundary_recording = create_boundary_root(minimum_role: :view)
    child = create_child_recording(boundary_recording, "Child")

    grant_container_access(@workspace, @actor, :edit)

    assert_equal :edit, AccessCheck.role_for(actor: @actor, recording: child)
  end

  # --- Query helper ---

  def test_access_recordings_for_returns_access_recordings
    page_recording = create_page_recording("Page")
    grant_access(page_recording, @actor, :edit)

    results = AccessCheck.access_recordings_for(page_recording)
    assert_equal 1, results.count
    assert_equal "RecordingStudio::Access", results.first.recordable_type
  end

  def test_allowed_returns_false_for_unknown_required_role
    page_recording = create_page_recording("Page")
    grant_access(page_recording, @actor, :admin)

    refute AccessCheck.allowed?(actor: @actor, recording: page_recording, role: :owner)
  end

  def test_container_lookup_returns_empty_for_unknown_minimum_role
    grant_container_access(@workspace, @actor, :admin)

    assert_equal [], AccessCheck.containers_for(actor: @actor, minimum_role: :owner)
    assert_equal [], AccessCheck.container_ids_for(actor: @actor, container_class: Workspace, minimum_role: :owner)
  end

  private

  def create_page_recording(title)
    page = RecordingStudioPage.create!(title: title)
    RecordingStudio::Recording.create!(
      container: @workspace,
      recordable: page
    )
  end

  def create_child_recording(parent, title)
    comment = RecordingStudioComment.create!(body: title)
    RecordingStudio::Recording.create!(
      container: @workspace,
      recordable: comment,
      parent_recording: parent
    )
  end

  def grant_access(recording, actor, role)
    access = RecordingStudio::Access.create!(actor: actor, role: role)
    RecordingStudio::Recording.create!(
      container: @workspace,
      recordable: access,
      parent_recording: recording
    )
  end

  def grant_container_access(container, actor, role)
    access = RecordingStudio::Access.create!(actor: actor, role: role)
    RecordingStudio::Recording.create!(
      container: container,
      recordable: access,
      parent_recording: nil
    )
  end

  def create_boundary_child(parent, minimum_role: nil)
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: minimum_role)
    RecordingStudio::Recording.create!(
      container: @workspace,
      recordable: boundary,
      parent_recording: parent
    )
  end

  def create_boundary_root(minimum_role: nil)
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: minimum_role)
    RecordingStudio::Recording.create!(
      container: @workspace,
      recordable: boundary,
      parent_recording: nil
    )
  end

  AccessCheck = RecordingStudio::Services::AccessCheck
end
