# frozen_string_literal: true

class AddRecordingStudioEventsTimelineIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :recording_studio_events,
              %i[occurred_at created_at id],
              order: { occurred_at: :desc, created_at: :desc, id: :desc },
              name: "index_rs_events_on_timeline",
              if_not_exists: true
  end
end
