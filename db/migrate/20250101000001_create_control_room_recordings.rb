# frozen_string_literal: true

class CreateControlRoomRecordings < ActiveRecord::Migration[7.1]
  def change
    create_table :control_room_recordings, id: :uuid do |t|
      t.string :recordable_type, null: false
      t.uuid :recordable_id, null: false
      t.string :container_type, null: false
      t.uuid :container_id, null: false
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :control_room_recordings, [:container_type, :container_id],
              name: "index_control_room_recordings_on_container"
    add_index :control_room_recordings, [:recordable_type, :recordable_id],
              name: "index_control_room_recordings_on_recordable"
  end
end
