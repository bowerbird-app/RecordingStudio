# frozen_string_literal: true

require "test_helper"

class EventRootTimelineTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
  end

  def test_root_recording_id_is_set_when_an_event_is_created
    _, root = create_workspace_root
    created = root.record(RecordingStudioPage) { |page| page.title = "Page" }
    child = root.record(RecordingStudioPage, parent_recording: created) { |page| page.title = "Child" }

    assert_equal root.id, created.events.first.root_recording_id
    assert_equal root.id, child.log_event!(action: "reviewed").root_recording_id

    direct = RecordingStudio::Event.create!(
      action: "noted",
      recordable: created.recordable,
      recording: created
    )
    assert_equal root.id, direct.root_recording_id
  end

  def test_cross_root_move_rewrites_subtree_event_roots_in_one_update
    _, root = create_workspace_root(name: "From")
    _, destination = create_workspace_root(name: "To")
    parent = root.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }
    grandchild = root.record(RecordingStudioPage, parent_recording: child) { |page| page.title = "Grandchild" }
    parent.log_event!(action: "parent-note")
    child.log_event!(action: "child-note")
    grandchild.log_event!(action: "grandchild-note")
    root_event = root.log_event!(action: "root-note")
    outsider = root.record(RecordingStudioPage) { |page| page.title = "Stays" }

    event_updates = []
    callback = lambda { |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      event_updates << sql if sql.match?(/UPDATE\s+"?recording_studio_events"?/i)
    }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      RecordingStudio::Recording.transaction do
        RecordingStudio::Recording.where(id: [child.id, grandchild.id]).update_all(root_recording_id: destination.id)
        parent.update!(parent_recording: destination, root_recording_id: destination.id)
      end
    end

    assert_equal 1, event_updates.size
    [parent, child, grandchild].each do |recording|
      assert_equal destination.id, recording.reload.root_recording_id
      recording.events.each do |event|
        assert_equal destination.id, event.reload.root_recording_id
      end
    end
    assert_equal root.id, root_event.reload.root_recording_id
    assert_equal root.id, outsider.reload.root_recording_id
    assert_equal root.id, outsider.events.first.root_recording_id

    moved = parent.log_event!(action: "after-move")
    assert_equal destination.id, moved.root_recording_id
    refute_includes RecordingStudio::Event.for_root(root).map(&:id), grandchild.events.pick(:id)
    assert_includes RecordingStudio::Event.for_root(destination).map(&:id), grandchild.events.pick(:id)
  end

  def test_root_timeline_uses_a_default_limit_and_keyset_cursor
    _, root = create_workspace_root
    page = root.record(RecordingStudioPage) { |page_record| page_record.title = "Timeline" }
    stamp = Time.utc(2026, 1, 1, 12, 0, 0)
    55.times { |index| page.log_event!(action: "tick-#{index}", occurred_at: stamp + index.minutes) }

    tied = page.events.order(:created_at).limit(2).to_a
    RecordingStudio::Event.where(id: tied.map(&:id)).update_all(occurred_at: stamp, created_at: stamp)

    expected = RecordingStudio::Event.where(root_recording_id: root.id)
                                     .order(occurred_at: :desc, created_at: :desc, id: :desc)
                                     .pluck(:id)

    first_page = root.events_query.to_a
    assert_equal RecordingStudio::Event::ROOT_TIMELINE_LIMIT, first_page.size
    assert_equal expected.first(50), first_page.map(&:id)

    cursor = RecordingStudio::Event.cursor_for(first_page.last)
    second_page = root.events_query(cursor: cursor).to_a
    assert_equal expected.drop(50), second_page.map(&:id)

    empty_page = root.events_query(cursor: RecordingStudio::Event.cursor_for(second_page.last)).to_a
    assert_empty empty_page

    tied_order = RecordingStudio::Event.where(id: tied.map(&:id))
                                       .order(occurred_at: :desc, created_at: :desc, id: :desc)
                                       .pluck(:id)
    tie_page = root.events_query(limit: 1, cursor: RecordingStudio::Event.cursor_for(
      RecordingStudio::Event.find(tied_order.first)
    )).to_a
    assert_equal [tied_order.second], tie_page.map(&:id)

    assert_equal 10, root.events_query(limit: 10).size
    assert_operator root.events_query(recording_id: page.id).size, :>, 50
    assert_raises(ArgumentError) { root.events_query(offset: 10) }
    assert_raises(ArgumentError) { root.events_query(cursor: "not-a-cursor") }
  end

  def test_root_wide_reads_use_the_event_root_column
    _, root = create_workspace_root
    page = root.record(RecordingStudioPage) { |page_record| page_record.title = "Filtered" }

    root_sql = root.events_query.to_sql
    assert_includes root_sql, "root_recording_id"
    assert_includes root_sql, "LIMIT"
    refute_match(/join/i, root_sql)
    refute_includes root_sql, "OFFSET"

    filtered_sql = root.events_query(recording_id: page.id).to_sql
    assert_includes filtered_sql, "recording_studio_recordings"
    refute_includes filtered_sql, "LIMIT"

    for_root_sql = RecordingStudio::Event.for_root(root).to_sql
    assert_includes for_root_sql, "root_recording_id"
    refute_match(/join/i, for_root_sql)
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.root_recording_for(workspace)]
  end
end
