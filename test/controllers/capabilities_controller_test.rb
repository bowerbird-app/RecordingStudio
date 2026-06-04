# frozen_string_literal: true

require "test_helper"

class CapabilitiesControllerTest < ActionDispatch::IntegrationTest
  EXPECTED_CAPABILITY_CATALOG_TEXT = [
    "Capabilities",
    "RecordingStudio.registered_capabilities",
    "RecordingStudio.register_capability",
    "RecordingStudio.capability_child_recordables_for",
    "RecordingStudio.child_recordable_types_for",
    "RecordingStudio.capability_allowed_parent_types_for",
    "RecordingStudio.recordable_parent_allowances_for",
    "RecordingStudio.parent_capabilities_for",
    "RecordingStudio.capability_enabled?",
    "RecordingStudio.capabilities_for",
    "RecordingStudio.capability_options",
    "recording.capability_enabled?",
    "recording.capability_options",
    "recording.capabilities",
    "recording.assert_capability!"
  ].freeze

  UNEXPECTED_CAPABILITY_CATALOG_TEXT = [
    "commentable",
    "recording.comment!",
    "recording.comments"
  ].freeze

  EXPECTED_CAPABILITY_RESPONSE_TEXT = [
    "# Response",
    "# Example response:",
    "child_recordables:",
    "recording_studio_reviewable",
    "[:reviewable]",
    "nil on success, or raises RecordingStudio::CapabilityDisabled",
    "flat-pack--section-title-anchor",
    "flat-pack--sidebar-group",
    ">Config<",
    ">Tree<",
    ">Capabilities<",
    "href=\"#recording-capability-enabled\""
  ].freeze

  setup do
    @user = create_user(name: "Capabilities Reader")
    sign_in_as(@user)
  end

  test "index renders capability catalog" do
    get capabilities_path, headers: modern_headers
    body = @response.body

    assert_response :success
    EXPECTED_CAPABILITY_CATALOG_TEXT.each { |text| assert body.include?(text), "missing expected text: #{text}" }
    UNEXPECTED_CAPABILITY_CATALOG_TEXT.each { |text| refute body.include?(text), "unexpected text present: #{text}" }
    EXPECTED_CAPABILITY_RESPONSE_TEXT.each { |text| assert body.include?(text), "missing expected text: #{text}" }
  end
end
