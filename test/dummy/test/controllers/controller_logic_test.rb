# frozen_string_literal: true

require_relative "../test_helper"

class ControllerLogicTest < ActiveSupport::TestCase
  def teardown
    Current.reset_all
  end

  test "application controller current_actor uses current_user" do
    user = User.create!(
      name: "Controller User",
      email: "controller-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    controller = ApplicationController.new
    controller.singleton_class.send(:define_method, :current_user) { user }

    assert_equal user, controller.send(:current_actor)
    assert_equal user, Current.actor
    assert_nil Current.impersonator
  end

  test "application controller root_recording_for looks up the workspace root" do
    workspace = Workspace.create!(name: "Workspace")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    controller = ApplicationController.new

    assert_equal root, controller.send(:root_recording_for, workspace)
  end
end
