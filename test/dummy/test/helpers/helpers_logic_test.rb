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
end
