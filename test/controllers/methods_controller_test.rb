# frozen_string_literal: true

require "test_helper"

class MethodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Docs Reader")
    sign_in_as(@user)
  end

  test "index renders method catalog" do
    get methods_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Methods"
    assert_includes @response.body, "RecordingStudio.configure"
    assert_includes @response.body, "root_recording.record"
    assert_includes @response.body, "recording.comment!"
  end
end
