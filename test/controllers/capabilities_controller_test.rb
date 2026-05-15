# frozen_string_literal: true

require "test_helper"

class CapabilitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Capabilities Reader")
    sign_in_as(@user)
  end

  test "index renders capability catalog" do
    get capabilities_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Capabilties"
    assert_includes @response.body, "RecordingStudio.register_capability"
    assert_includes @response.body, "RecordingStudio.capability_enabled?"
    assert_includes @response.body, "RecordingStudio.capabilities_for"
    assert_includes @response.body, "RecordingStudio.capability_options"
    assert_includes @response.body, "recording.capability_enabled?"
    assert_includes @response.body, "recording.capability_options"
    assert_includes @response.body, "recording.capabilities"
    assert_includes @response.body, "recording.assert_capability!"
    assert_includes @response.body, "# Response"
    assert_includes @response.body, "# Example response:"
    refute_includes @response.body, "commentable"
    refute_includes @response.body, "recording.comment!"
    refute_includes @response.body, "recording.comments"
    assert_includes @response.body, "[:reviewable]"
    assert_includes @response.body, "nil on success, or raises RecordingStudio::CapabilityDisabled"
    assert_includes @response.body, "flat-pack--section-title-anchor"
    assert_includes @response.body, "flat-pack--sidebar-group"
    assert_includes @response.body, ">Config<"
    assert_includes @response.body, ">Tree<"
    assert_includes @response.body, ">Capabilties<"
    assert_includes @response.body, "href=\"#recording-capability-enabled\""
  end
end
