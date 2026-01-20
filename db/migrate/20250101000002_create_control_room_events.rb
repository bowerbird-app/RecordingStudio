# frozen_string_literal: true

class CreateControlRoomEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :control_room_events, id: :uuid do |t|
      t.references :recording, null: false, type: :uuid,
                               foreign_key: { to_table: :control_room_recordings }
      t.string :action, null: false
      t.string :recordable_type, null: false
      t.uuid :recordable_id, null: false
      t.string :previous_recordable_type
      t.uuid :previous_recordable_id
      t.string :actor_type
      t.uuid :actor_id
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.jsonb :metadata, null: false, default: {}
      t.string :idempotency_key

      t.timestamps
    end

    add_index :control_room_events, [:recording_id, :idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_control_room_events_on_recording_and_idempotency_key"
  end
end
