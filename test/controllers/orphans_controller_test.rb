# frozen_string_literal: true

require "test_helper"

class OrphansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Orphans Reader")
    sign_in_as(@user)
  end

  test "index renders overview copy" do
    request_orphans

    assert_includes @response.body, "Orphans"
    assert_includes @response.body, "How RecordingStudio handles records without a parent."
    assert_includes @response.body, "Orphans are not allowed. All recordings except roots must have a parent."
    assert_includes @response.body, "Allowed parent types are defined in recordables using"
    assert_includes @response.body, "recording_studio_recordable"
    refute_includes @response.body, "What Counts as an Orphan"
    refute_includes @response.body, "Security Checks"
  end

  test "index renders orphan helper examples" do
    request_orphans

    assert_select "div.rounded-lg.flex.flex-col ul[role='list']", count: 1
    assert_includes @response.body, "recording.parentless?"
    assert_includes @response.body, "Checks whether a recording has no parent_recording_id."
    assert_includes @response.body, "Parentless check"
    assert_includes @response.body, "true when parent_recording_id is blank"
    assert_includes @response.body, "recording.orphan?"
    assert_includes @response.body, "Checks whether a recording is parentless and is not a valid root."
    assert_includes @response.body, "Orphan check"
    assert_includes @response.body, "recording.parentless? &amp;&amp; !recording.root?"
    assert_includes @response.body, "RecordingStudio::Recording.where(parent_recording_id: nil)"
    assert_includes @response.body, "Finds parentless recordings, including valid roots."
    assert_includes @response.body, "Parentless query"
    assert_includes @response.body, "parentless_recordings = RecordingStudio::Recording.where(parent_recording_id: nil)"
    assert_includes @response.body, "orphan_recordings = parentless_recordings.select(&amp;:orphan?)"

    assert_select "div#recording-parentless.fp-section-title-anchor a[href='#recording-parentless']", count: 1
    assert_select "div#recording-orphan.fp-section-title-anchor a[href='#recording-orphan']", count: 1

    parentless_query_selector = "div#recordingstudio-recording-where-parent_recording_id-nil.fp-section-title-anchor " \
                                "a[href='#recordingstudio-recording-where-parent_recording_id-nil']"
    assert_select parentless_query_selector, count: 1
  end

  test "index renders orphan error messages" do
    request_orphans

    assert_includes @response.body, "Error Messages"
    assert_includes @response.body, "Returned when trying to create a non-root recording without a parent."
    assert_includes @response.body, "Returned errors"
    assert_includes @response.body, "RecordingStudio::RootNotAllowed"
    assert_includes @response.body, "parent_recording_id is required for RecordingStudioPage"
    assert_includes @response.body, "parent_recording_id"
    assert_includes(
      @response.body,
      "parent_recording_id: is required for RecordingStudioPage"
    )

    assert_select "div#error-messages.fp-section-title-anchor a[href='#error-messages']", count: 1
    assert_select "table", count: 0
    assert_select "pre code.language-text", count: 1
  end

  test "index renders navigation state" do
    request_orphans

    assert_includes @response.body, "href=\"/orphans\""
    assert_includes @response.body, ">Orphans<"

    methods_index = @response.body.index("href=\"/methods\"")
    orphans_index = @response.body.index("href=\"/orphans\"")

    assert_not_nil methods_index
    assert_not_nil orphans_index
    assert_operator methods_index, :<, orphans_index

    open_sidebar_link = "div[data-controller='flat-pack--sidebar-group']" \
                        "[data-flat-pack--sidebar-group-default-open-value='true'] " \
                        "div[data-flat-pack--sidebar-group-target='panel'] a[href='/orphans']"
    assert_select open_sidebar_link, count: 1
  end

  private

  def request_orphans
    get orphans_path, headers: modern_headers

    assert_response :success
  end
end
