# frozen_string_literal: true

require "test_helper"

class ConfigurableLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Layout Config User")
    sign_in_as(@user)
    @original_layout = RecordingStudio.configuration.layout
  end

  teardown do
    RecordingStudio.configuration.layout = @original_layout
  end

  test "unset layout config keeps the default layout" do
    assert_nil RecordingStudio.configuration.layout

    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
  end

  test "string layout config selects that layout" do
    RecordingStudio.configuration.layout = "application"

    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 0
    assert_includes @response.body, "Default Layout Demo"
  end

  test "callable layout config receives the controller" do
    seen = nil
    RecordingStudio.configuration.layout = lambda { |controller:|
      seen = controller
      "application"
    }

    get layout_demo_path, headers: modern_headers

    assert_response :success
    assert_equal "LayoutDemoController", seen.class.name
    assert_select "body[data-recording-studio-default-layout='true']", count: 0
  end
end
