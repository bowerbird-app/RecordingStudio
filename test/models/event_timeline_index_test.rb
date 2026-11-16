# frozen_string_literal: true

require "test_helper"

class EventTimelineIndexTest < ActiveSupport::TestCase
  def test_global_timeline_index_orders_newest_occurred_at_created_at_and_id_first
    index = RecordingStudio::Event.connection.indexes(:recording_studio_events).find do |candidate|
      candidate.name == "index_rs_events_on_timeline"
    end

    assert index
    assert_equal %w[occurred_at created_at id], Array(index.columns)
    assert_equal :desc, index.orders
  end
end
