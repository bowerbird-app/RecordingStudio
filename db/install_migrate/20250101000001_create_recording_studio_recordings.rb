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

      t.timestamps
    end

    add_index :recording_studio_recordings, :parent_recording_id
    add_index :recording_studio_recordings, %i[recordable_type recordable_id],
              name: "index_recording_studio_recordings_on_recordable"
    add_index :recording_studio_recordings, :root_recording_id,
              name: "index_rs_recordings_on_root_recording"
    add_index :recording_studio_recordings,
              %i[recordable_type recordable_id],
              unique: true,
              where: "parent_recording_id IS NULL",
              name: "index_rs_unique_root_recording_per_recordable"
    add_index :recording_studio_recordings,
              %i[root_recording_id parent_recording_id],
              name: "index_rs_recordings_on_root_and_parent"
    add_index :recording_studio_recordings,
              %i[root_recording_id recordable_type recordable_id],
              name: "index_rs_recordings_on_root_and_recordable"

    add_foreign_key :recording_studio_recordings, :recording_studio_recordings, column: :parent_recording_id
    add_foreign_key :recording_studio_recordings, :recording_studio_recordings, column: :root_recording_id
  end
  # rubocop:enable Metrics/MethodLength
end
