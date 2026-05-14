# frozen_string_literal: true

require "test_helper"

class ConfigControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Config Reader")
    sign_in_as(@user)
  end

  test "index renders recording studio configuration" do
    get recording_studio_config_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Config"
    assert_includes @response.body, "RecordingStudio.configure"
    assert_includes @response.body, "config.event_notifications_enabled = true"
    assert_includes @response.body, "config.recordable_dup_strategy = :dup"
  end
end
