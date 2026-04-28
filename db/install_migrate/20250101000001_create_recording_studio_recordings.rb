# frozen_string_literal: true

class CreateRecordingStudioRecordings < ActiveRecord::Migration[8.1]
  # Historical install migration kept verbose for readability.
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :recording_studio_recordings, id: :uuid do |t|
      t.string :recordable_type, null: false
      t.uuid :recordable_id, null: false
      t.uuid :parent_recording_id
      t.uuid :root_recording_id
      t.datetime :trashed_at

      t.timestamps
    end

    add_index :recording_studio_recordings, :parent_recording_id
    add_index :recording_studio_recordings, %i[recordable_type recordable_id],
              name: "index_recording_studio_recordings_on_recordable"
    add_index :recording_studio_recordings, %i[recordable_type recordable_id parent_recording_id trashed_at],
              name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    add_index :recording_studio_recordings, :root_recording_id,
              name: "index_rs_recordings_on_root_recording"

    add_foreign_key :recording_studio_recordings, :recording_studio_recordings, column: :parent_recording_id
    add_foreign_key :recording_studio_recordings, :recording_studio_recordings, column: :root_recording_id
  end
  # rubocop:enable Metrics/MethodLength
end
