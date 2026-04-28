# frozen_string_literal: true

class CreateRecordingStudioEvents < ActiveRecord::Migration[8.1]
  # Historical install migration kept as a single change block.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
