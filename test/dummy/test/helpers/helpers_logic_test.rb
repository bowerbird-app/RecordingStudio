# frozen_string_literal: true

require_relative "../test_helper"

class HelpersLogicTest < ActiveSupport::TestCase
  test "actor_switcher_options builds grouped options and selected system actor" do
    true_user = User.create!(
      name: "True User",
      email: "true-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    other_user = User.create!(
      name: "Other User",
      email: "other-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    system_actor = SystemActor.create!(name: "Background Task")

    grouped, selected, label = ApplicationController.helpers.actor_switcher_options(
      current_actor: system_actor,
      current_user: true_user,
      true_user: true_user,
      system_actors: [ system_actor ],
      impersonating: false
    )

    assert_equal "SystemActor:#{system_actor.id}", selected
    assert_equal "Signed in as #{true_user.name}", label
    assert_includes grouped.fetch("Users"), [ other_user.name, "User:#{other_user.id}" ]
    assert_includes grouped.fetch("System actors"), [ "#{system_actor.name} (System)", "SystemActor:#{system_actor.id}" ]
  end

  test "actor label and impersonator label format correctly" do
    user = User.create!(
      name: "Labeled User",
      email: "label-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    system_actor = SystemActor.create!(name: "Bot")

    assert_equal "System", ApplicationController.helpers.actor_label(nil)
    assert_equal "Labeled User (User)", ApplicationController.helpers.actor_label(user)
    assert_equal "Bot (System)", ApplicationController.helpers.actor_label(system_actor)
    assert_equal "Labeled User (User) (impersonated by Bot (System))",
                 ApplicationController.helpers.actor_with_impersonator_label(user, system_actor)
  end

  test "recordable_label handles access boundary and generic title" do
    user = User.create!(
      name: "Access User",
      email: "access-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    access = RecordingStudio::Access.create!(actor: user, role: :admin)
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :edit)
    page = RecordingStudioPage.create!(title: "A Titled Page")

    assert_equal "Access: admin — Access User (User)", ApplicationController.helpers.recordable_label(access)
    assert_equal "Access boundary (min: edit)", ApplicationController.helpers.recordable_label(boundary)
    assert_equal "A Titled Page", ApplicationController.helpers.recordable_label(page)
  end

  test "recordable_label handles comment snippets and blank comment" do
    comment = RecordingStudioComment.create!(body: "This is a very long comment body that should still render as a comment snippet for labels")
    blank_comment = RecordingStudioComment.new(body: " ")

    assert_includes ApplicationController.helpers.recordable_label(comment), "Comment:"
    assert_equal "Comment", ApplicationController.helpers.recordable_label(blank_comment)
  end

  test "recordable_label handles boundary without minimum and unknown fallback" do
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: nil)
    fallback_class = Class.new do
      attr_reader :id

      def initialize(id)
        @id = id
      end
    end
    Object.const_set("FallbackThing", fallback_class)
    fallback = FallbackThing.new("x-1")

    assert_equal "Access boundary", ApplicationController.helpers.recordable_label(boundary)
    assert_equal "FallbackThing #x-1", ApplicationController.helpers.recordable_label(fallback)
    assert_equal "—", ApplicationController.helpers.recordable_label(nil)
  ensure
    Object.send(:remove_const, :FallbackThing) if Object.const_defined?(:FallbackThing)
  end

  test "recordings_hierarchy_list renders nested list" do
    workspace = Workspace.create!(name: "Helper Workspace")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    child = RecordingStudio::Recording.create!(
      root_recording: root,
      parent_recording: root,
      recordable: RecordingStudioPage.create!(title: "Child Page")
    )

    grouped = {
      nil => [ root ],
      root.id => [ child ]
    }

    helpers = ApplicationController.helpers
    helpers.singleton_class.send(:define_method, :recording_path) { |recording| "/recordings/#{recording.id}" }

    html = helpers.recordings_hierarchy_list(grouped)

    assert_includes html, "Child Page"
    assert_includes html, "list-disc"
  end

  test "actor_switcher_options selects impersonated user" do
    true_user = User.create!(
      name: "True User",
      email: "true-user-imp-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    impersonated_user = User.create!(
      name: "Impersonated",
      email: "imp-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    grouped, selected, _label = ApplicationController.helpers.actor_switcher_options(
      current_actor: impersonated_user,
      current_user: impersonated_user,
      true_user: true_user,
      system_actors: [],
      impersonating: true
    )

    assert_equal "User:#{impersonated_user.id}", selected
    refute grouped.key?("System actors")
  end

  test "actor_switcher_options uses current_actor when current_user differs" do
    true_user = User.create!(
      name: "True User Selected",
      email: "true-user-selected-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    impersonated_user = User.create!(
      name: "Impersonated Selected",
      email: "imp-selected-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    _grouped, selected, _label = ApplicationController.helpers.actor_switcher_options(
      current_actor: impersonated_user,
      current_user: true_user,
      true_user: true_user,
      system_actors: [],
      impersonating: true
    )

    assert_equal "User:#{impersonated_user.id}", selected
  end

  test "recordable_type_label handles class string instance and blank" do
    page = RecordingStudioPage.create!(title: "Type Page")

    assert_equal "Page", ApplicationController.helpers.recordable_type_label("RecordingStudioPage")
    assert_equal "Page", ApplicationController.helpers.recordable_type_label(RecordingStudioPage)
    assert_equal "Page", ApplicationController.helpers.recordable_type_label(page)
    assert_equal "Unknown type", ApplicationController.helpers.recordable_type_label("UnknownType")
    assert_equal "—", ApplicationController.helpers.recordable_type_label(nil)
  end

  test "recordable_title falls back from title to name to label" do
    page = RecordingStudioPage.create!(title: "  Squished   Title  ")
    folder = RecordingStudioFolder.create!(name: " Folder Name ")
    nameless_class = Class.new do
      attr_reader :id

      def initialize(id)
        @id = id
      end
    end
    Object.const_set("TitleFallbackThing", nameless_class)
    nameless = TitleFallbackThing.new(55)

    assert_equal "Squished Title", ApplicationController.helpers.recordable_title(page)
    assert_equal "Folder Name", ApplicationController.helpers.recordable_title(folder)
    assert_equal "TitleFallbackThing #55", ApplicationController.helpers.recordable_title(nameless)
    assert_equal "—", ApplicationController.helpers.recordable_title(nil)
  ensure
    Object.send(:remove_const, :TitleFallbackThing) if Object.const_defined?(:TitleFallbackThing)
  end

  test "recordable_summary uses summary then truncated body then nil" do
    summary_class = Class.new do
      def summary
        "  Already summarized  "
      end
    end
    Object.const_set("SummaryThing", summary_class)

    long_text = "word " * 80
    body_class = Class.new do
      define_method(:initialize) { |body| @body = body }
      attr_reader :body
    end
    Object.const_set("BodyThing", body_class)

    assert_equal "Already summarized", ApplicationController.helpers.recordable_summary(SummaryThing.new)

    truncated = ApplicationController.helpers.recordable_summary(BodyThing.new(long_text))
    assert truncated.length <= 160
    assert_includes truncated, "..."

    no_content = Struct.new(:summary, :body).new(nil, nil)
    assert_nil ApplicationController.helpers.recordable_summary(no_content)
    assert_nil ApplicationController.helpers.recordable_summary(nil)
  ensure
    Object.send(:remove_const, :SummaryThing) if Object.const_defined?(:SummaryThing)
    Object.send(:remove_const, :BodyThing) if Object.const_defined?(:BodyThing)
  end

  test "recordings_hierarchy_list renders boundary badge" do
    workspace = Workspace.create!(name: "Boundary Workspace")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :edit)
    boundary_recording = RecordingStudio::Recording.create!(
      root_recording: root,
      parent_recording: root,
      recordable: boundary
    )

    grouped = {
      nil => [ root ],
      root.id => [ boundary_recording ]
    }

    helpers = ApplicationController.helpers
    helpers.singleton_class.send(:define_method, :recording_path) { |recording| "/recordings/#{recording.id}" }

    html = helpers.recordings_hierarchy_list(grouped)

    assert_includes html, "🔒 Boundary (min: edit)"
    assert_includes html, "rounded bg-slate-100"
  end

  test "workspace_switcher_options returns only accessible workspaces and selected workspace" do
    actor = User.create!(
      name: "Workspace Actor",
      email: "workspace-actor-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    allowed_workspace = Workspace.create!(name: "Allowed Workspace")
    denied_workspace = Workspace.create!(name: "Denied Workspace")
    allowed_root = RecordingStudio::Recording.create!(recordable: allowed_workspace)
    RecordingStudio::Recording.create!(recordable: denied_workspace)

    RecordingStudio::Services::AccessCheck.stub(:root_recording_ids_for, [ allowed_root.id ]) do
      options, selected_workspace_id = ApplicationController.helpers.workspace_switcher_options(
        current_actor: actor,
        current_root_recording: allowed_root
      )

      assert_equal [ [ "Allowed Workspace", allowed_workspace.id ] ], options
      assert_equal allowed_workspace.id, selected_workspace_id
    end
  end
end
