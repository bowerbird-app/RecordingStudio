# frozen_string_literal: true

require "test_helper"

class DummyAppSmokeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    Page.delete_all
    Workspace.delete_all
    User.delete_all
    SystemActor.delete_all

    @admin = User.create!(name: "Admin", email: "admin@example.com", password: "password123", admin: true)
    sign_in @admin

    @workspace = Workspace.create!(name: "Workspace")
    @recording = @workspace.record(Page, actor: @admin) { |page| page.title = "Draft" }
  end

  def teardown
    Current.reset_all
  end

  def test_home_page_renders
    get root_path

    assert_response :success
    assert_includes response.body, "Recording Studio"
    assert_includes response.body, "Actor"
  end

  def test_events_index_renders
    get events_path

    assert_response :success
    assert_includes response.body, "Events"
  end

  def test_recordings_index_and_show_render
    get recordings_path
    assert_response :success

    get recording_path(@recording)
    assert_response :success
    assert_includes response.body, "Draft"
  end

  def test_recording_log_event_and_revert
    assert_difference -> { @recording.events.count }, 1 do
      post log_event_recording_path(@recording)
    end
    follow_redirect!
    assert_response :success

    assert_difference -> { @recording.events.count }, 1 do
      post revert_recording_path(@recording), params: { recordable_id: @recording.recordable_id }
    end
    follow_redirect!
    assert_response :success
  end
end
