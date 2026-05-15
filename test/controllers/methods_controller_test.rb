# frozen_string_literal: true

require "test_helper"

class MethodsControllerTest < ActionDispatch::IntegrationTest
  CRUD_EVENT_HTML =
    "#&lt;RecordingStudio::Event id: " \
    "&quot;1f94e2f4-7a5d-4f4d-8f3c-3d5d7762c114&quot;, action: " \
    "&quot;created&quot;, recording_id: " \
    "&quot;7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9&quot;&gt;"
  TREE_RECORDING_HTML =
    "#&lt;RecordingStudio::Recording id: " \
    "&quot;5c0f9d52-5401-4cfa-af8b-dfb3c436d7cb&quot;, recordable_type: " \
    "&quot;Folder&quot;, recordable_id: " \
    "&quot;99ef1584-18da-42f4-98a4-9922633bf05b&quot;&gt;"
  CONFIGURE_RETURNS_TEXT =
    "# Returns: Block return value; " \
    "use this API to mutate RecordingStudio::Configuration rather than read data."
  IDENTITY_GID_HTML = "&quot;gid://recording-studio/Workspace/1&quot;"
  setup do
    @user = create_user(name: "Docs Reader")
    sign_in_as(@user)
  end

  test "method catalog stays separate from specialized method pages" do
    method_subtitles = MethodsController::METHOD_CATALOG.map { |entry| entry.fetch(:subtitle) }

    assert_equal method_subtitles.uniq.length, method_subtitles.length
    assert_equal MethodsController::ROOT_METHOD_SUBTITLES.uniq.length, MethodsController::ROOT_METHOD_SUBTITLES.length
  end

  test "index renders method catalog" do
    get methods_path, headers: modern_headers

    assert_response :success
    assert_index_catalog_content
    assert_response_details_present
    assert_includes @response.body, CONFIGURE_RETURNS_TEXT
    assert_includes @response.body, "config.recordable_types"
    assert_includes @response.body, "RecordingStudio::Configuration"
    assert_includes @response.body, "href=\"#recordingstudio-configure\""
  end

  test "identity renders identity method catalog" do
    get identity_methods_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Identity"
    assert_includes @response.body, "RecordingStudio.recordable_type_name"
    assert_includes @response.body, "RecordingStudio.resolve_recordable_type"
    assert_includes @response.body, "RecordingStudio.recordable_identifier"
    assert_includes @response.body, "RecordingStudio.recordable_global_id"
    assert_includes @response.body, "RecordingStudio.recordable_name"
    assert_includes @response.body, "RecordingStudio.recordable_type_label"
    assert_includes @response.body, "recording.name"
    assert_includes @response.body, "recording.type_label"
    assert_includes @response.body, "GlobalID string or nil"
    assert_includes @response.body, IDENTITY_GID_HTML
    assert_includes @response.body, "Report blue"
    refute_includes @response.body, "root_recording.record"
    assert_includes @response.body, "href=\"#recordingstudio-recordable-type-name\""
    assert_includes @response.body, "href=\"#recording-name\""
  end

  test "crud renders CRUD method catalog" do
    get crud_methods_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "CRUD"
    assert_includes @response.body, "RecordingStudio.record!"
    assert_includes @response.body, CRUD_EVENT_HTML
    assert_includes @response.body, "RecordingStudio.dup_strategy_for"
    assert_includes @response.body, "RecordingStudio.duplicate_recordable"
    refute_includes @response.body, "root_recording.record"
    refute_includes @response.body, "root_recording.revise"
    refute_includes @response.body, "root_recording.revert"
    refute_includes @response.body, "RecordingStudio.recordable_type_name"
    assert_includes @response.body, "href=\"#recordingstudio-record\""
  end

  test "events renders event method catalog" do
    get event_methods_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Events"
    refute_includes @response.body, "RecordingStudio.record!"
    refute_includes @response.body, "root_recording.log_event"
    assert_includes @response.body, "recording.log_event!"
    assert_includes @response.body, "recording.events"
    assert_includes @response.body, "recording.latest_event"
    assert_includes @response.body, "recording.first_event"
    assert_includes @response.body, "recording.event_by_idempotency_key"
    assert_includes @response.body, "recording.subtree_events"
    refute_includes @response.body, "RecordingStudio::Event.for_root"
    assert_includes @response.body, "RecordingStudio::Event.by_impersonator"
    assert_includes @response.body, "RecordingStudio::Event.between"
    assert_includes @response.body, "RecordingStudio::Event"
    assert_includes @response.body, "ActiveRecord::Relation&lt;RecordingStudio::Event&gt;"
    assert_response_details_present
    assert_event_catalog_notes
    assert_event_catalog_links
  end

  test "root renders root method catalog" do
    get root_methods_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Root"
    assert_includes @response.body, "RecordingStudio.root_recording_for"
    assert_includes @response.body, "root_recording.record"
    assert_includes @response.body, "root_recording.revise"
    assert_includes @response.body, "root_recording.log_event"
    assert_includes @response.body, "root_recording.revert"
    assert_includes @response.body, "root_recording.recordings_query"
    assert_includes @response.body, "root_recording.recordings_of"
    assert_includes @response.body, "root_recording.recording_for"
    assert_includes @response.body, "root_recording.recordings_for"
    assert_includes @response.body, "root_recording.recordables_of"
    assert_includes @response.body, "root_recording.child_recordings_of"
    assert_includes @response.body, "root_recording.events_query"
    assert_includes @response.body, "root_recording.recordings_with_events"
    assert_includes @response.body, "RecordingStudio::Recording.for_root"
    assert_includes @response.body, "RecordingStudio::Event.for_root"
    assert_includes @response.body, "href=\"#recordingstudio-root-recording-for\""
    assert_includes @response.body, "href=\"#recordingstudio-recording-for-root\""
    assert_includes @response.body, "href=\"#recordingstudio-event-for-root\""
    assert_includes @response.body, "href=\"#root-recording-events-query\""
  end

  test "queries renders query method catalog" do
    get query_methods_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Queries"
    assert_includes @response.body, "RecordingStudio::Recording.all"
    assert_includes @response.body, "RecordingStudio::Recording.of_type"
    assert_includes @response.body, "root_recording.recordings_query"
    assert_includes @response.body, "RecordingStudio::Event.for_recording"
    assert_includes @response.body, "recording.subtree_recordings"
    assert_includes @response.body, "href=\"#recordingstudio-recording-all\""
    assert_includes @response.body, "href=\"#recordingstudio-recording-of-type\""
    assert_includes @response.body, "href=\"#root-recording-recordings-query\""
    assert_includes @response.body, "href=\"#recordingstudio-event-for-recording\""
    assert_includes @response.body, "href=\"#recording-subtree-recordings\""
  end

  test "tree renders traversal method catalog" do
    get tree_methods_path, headers: modern_headers

    assert_response :success
    assert_includes @response.body, "Tree"
    assert_includes @response.body, "recording.parent_recording"
    assert_includes @response.body, "recording.child_recordings"
    assert_includes @response.body, "recording.ancestors"
    assert_includes @response.body, "recording.self_and_ancestors"
    assert_includes @response.body, "recording.descendants"
    assert_includes @response.body, "recording.self_and_descendants"
    assert_includes @response.body, "recording.root?"
    assert_includes @response.body, "recording.leaf?"
    assert_includes @response.body, "recording.depth"
    assert_includes @response.body, "recording.level"
    assert_includes @response.body, "Array&lt;RecordingStudio::Recording&gt;"
    assert_includes @response.body, "true or false"
    assert_includes @response.body, "# Example response:"
    assert_includes @response.body, TREE_RECORDING_HTML
    assert_catalog_sidebar
    assert_includes @response.body, "href=\"#recording-ancestors\""
  end

  private

  def assert_index_catalog_content
    assert_includes @response.body, "Config"
    assert_includes @response.body, "RecordingStudio.configure"
    assert_includes @response.body, "RecordingStudio.register_recordable_type"
    refute_includes @response.body, "RecordingStudio.recordable_type_name"
    refute_includes @response.body, "root_recording.record"
    refute_includes @response.body, "RecordingStudio.record!"
    refute_includes @response.body, "root_recording.recordings_query"
    refute_includes @response.body, "RecordingStudio.capability_enabled?"
    refute_includes @response.body, "recording.capability_enabled?"
    assert_catalog_sidebar
  end

  def assert_catalog_sidebar
    assert_includes @response.body, "flat-pack--section-title-anchor"
    assert_includes @response.body, "flat-pack--sidebar-group"
    assert_includes @response.body, ">Config<"
    assert_includes @response.body, ">Identity<"
    assert_includes @response.body, ">CRUD<"
    assert_includes @response.body, ">Events<"
    assert_includes @response.body, ">Root<"
    assert_includes @response.body, ">Queries<"
    assert_includes @response.body, ">Tree<"
    assert_includes @response.body, ">Capabilties<"
  end

  def assert_response_details_present
    assert_includes @response.body, "# Response"
    assert_includes @response.body, "# Example response:"
  end

  def assert_event_catalog_notes
    assert_includes @response.body, "ordered newest first by occurred_at and then created_at"
    assert_includes @response.body, "limit and offset apply to that combined ordered result"
    refute_includes @response.body, "root_recording.recordings_query"
    refute_includes @response.body, "root_recording.log_event"
  end

  def assert_event_catalog_links
    assert_includes @response.body, "href=\"#recording-events\""
    assert_includes @response.body, "href=\"#recording-latest-event\""
    assert_includes @response.body, "href=\"#recording-first-event\""
    assert_includes @response.body, "href=\"#recording-event-by-idempotency-key\""
    assert_includes @response.body, "href=\"#recording-subtree-events\""
    assert_includes @response.body, "href=\"#recordingstudio-event-by-impersonator\""
    assert_includes @response.body, "href=\"#recordingstudio-event-between\""
  end
end
