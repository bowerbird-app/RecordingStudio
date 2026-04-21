# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  def setup
    User.delete_all
    SystemActor.delete_all

    @user = User.create!(name: "User", email: "user@example.com", password: "password123")
    @system_actor = SystemActor.create!(name: "Background task")
  end

  def test_actor_label_helpers
    assert_equal "System", actor_label(nil)
    assert_equal "#{@system_actor.name} (System)", actor_label(@system_actor)
    assert_equal "#{@user.name} (User)", actor_label(@user)

    label = actor_with_impersonator_label(@user, @system_actor)
    assert_includes label, "impersonated by"
  end

  def test_recordable_name_uses_name_when_title_is_missing
    workspace = Workspace.create!(name: "Studio Workspace")

    assert_equal "Studio Workspace", recordable_name(workspace)
  end

  def test_recordable_type_label_uses_recordable_contract
    folder = RecordingStudioFolder.create!(name: "Projects")

    assert_equal "Folder", recordable_type_label(folder)
  end

  def test_recordable_title_uses_name_for_folder
    folder = RecordingStudioFolder.create!(name: "Projects")

    assert_equal "Projects", recordable_title(folder)
  end

  def test_recordable_summary_falls_back_to_body
    comment = RecordingStudioComment.create!(body: "This is a test comment body")

    assert_equal "This is a test comment body", recordable_summary(comment)
  end
end
