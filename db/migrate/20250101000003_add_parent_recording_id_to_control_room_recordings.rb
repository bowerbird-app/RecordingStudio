# frozen_string_literal: true

class AddParentRecordingIdToControlRoomRecordings < ActiveRecord::Migration[7.1]
  def change
    add_column :control_room_recordings, :parent_recording_id, :uuid
    add_index :control_room_recordings, :parent_recording_id
    add_foreign_key :control_room_recordings, :control_room_recordings, column: :parent_recording_id
  end
end
