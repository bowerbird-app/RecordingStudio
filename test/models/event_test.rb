# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = ["Page"]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.delete_all
    Page.delete_all
    Workspace.delete_all
    User.delete_all
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_scopes_filter_events
    workspace = Workspace.create!(name: "Workspace")
    actor = User.create!(name: "Actor")
    recording = RecordingStudio.record!(
      action: "created",
      recordable: Page.new(title: "One"),
      container: workspace,
      occurred_at: 3.days.ago
    ).recording

    created = recording.log_event!(action: "created", actor: actor, occurred_at: 2.days.ago)
    updated = recording.log_event!(action: "updated", actor: actor, occurred_at: 1.day.ago)

    assert_includes RecordingStudio::Event.for_recording(recording), created
    assert_includes RecordingStudio::Event.with_action("updated"), updated
    assert_equal 0, RecordingStudio::Event.by_actor(nil).count
    assert_equal 2, RecordingStudio::Event.by_actor(actor).count
    assert_equal updated.id, RecordingStudio::Event.recent.first.id
  end

  def test_events_count_updates_on_create_and_destroy
    workspace = Workspace.create!(name: "Workspace")
    page = Page.new(title: "Page")
    event = RecordingStudio.record!(action: "created", recordable: page, container: workspace)

    page.reload
    assert_equal 1, page.events_count

    event.destroy!
    page.reload
    assert_equal 0, page.events_count
  end
end
