# frozen_string_literal: true

class CreateRecordingStudioEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_events, id: :uuid do |t|
      t.references :recording, null: false, type: :uuid,
                               foreign_key: { to_table: :recording_studio_recordings }
      t.string :action, null: false
      t.string :recordable_type, null: false
      t.uuid :recordable_id, null: false
      t.string :previous_recordable_type
      t.uuid :previous_recordable_id
      t.string :actor_type
      t.uuid :actor_id
      t.string :impersonator_type
      t.uuid :impersonator_id
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.jsonb :metadata, null: false, default: {}
      t.string :idempotency_key

      t.datetime :created_at, null: false
    end

    add_index :recording_studio_events, %i[recording_id idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_recording_studio_events_on_recording_and_idempotency_key"
    add_index :recording_studio_events,
              %i[recording_id occurred_at created_at],
              order: { occurred_at: :desc, created_at: :desc },
              name: "index_rs_events_on_recording_and_timeline"
    add_index :recording_studio_events,
              %i[action occurred_at],
              name: "index_rs_events_on_action_and_occurred_at"
    add_index :recording_studio_events,
              %i[actor_type actor_id occurred_at],
              name: "index_rs_events_on_actor_and_occurred_at"
  end
end
