# frozen_string_literal: true

class ReplaceContainerWithRootRecording < ActiveRecord::Migration[8.1]
  def up
    add_column :recording_studio_recordings, :root_recording_id, :uuid
    execute <<~SQL.squish
      WITH roots AS (
        SELECT container_type,
               container_id,
               MIN(id::text)::uuid AS id
        FROM recording_studio_recordings
        WHERE parent_recording_id IS NULL
          AND recordable_type = container_type
          AND recordable_id = container_id
        GROUP BY container_type, container_id
      )
      UPDATE recording_studio_recordings AS recording
      SET root_recording_id = root.id
      FROM roots AS root
      WHERE root.container_type = recording.container_type
        AND root.container_id = recording.container_id
    SQL

    missing_root_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM recording_studio_recordings
      WHERE root_recording_id IS NULL
    SQL
    if missing_root_count.positive?
      raise ActiveRecord::MigrationError,
            "cannot replace container columns because #{missing_root_count} recording(s) do not have a root recording"
    end

    add_index :recording_studio_recordings, :root_recording_id, name: "index_rs_recordings_on_root_recording"
    add_foreign_key :recording_studio_recordings, :recording_studio_recordings, column: :root_recording_id

    remove_index :recording_studio_recordings, name: "index_recording_studio_recordings_on_container", if_exists: true
    remove_column :recording_studio_recordings, :container_type, :string
    remove_column :recording_studio_recordings, :container_id, :uuid
  end

  def down
    add_column :recording_studio_recordings, :container_type, :string
    add_column :recording_studio_recordings, :container_id, :uuid
    execute <<~SQL.squish
      UPDATE recording_studio_recordings AS recording
      SET container_type = root.recordable_type,
          container_id = root.recordable_id
      FROM recording_studio_recordings AS root
      WHERE root.id = COALESCE(recording.root_recording_id, recording.id)
    SQL
    change_column_null :recording_studio_recordings, :container_type, false
    change_column_null :recording_studio_recordings, :container_id, false
    add_index :recording_studio_recordings, %i[container_type container_id],
              name: "index_recording_studio_recordings_on_container"

    remove_foreign_key :recording_studio_recordings, column: :root_recording_id
    remove_index :recording_studio_recordings, name: "index_rs_recordings_on_root_recording", if_exists: true
    remove_column :recording_studio_recordings, :root_recording_id, :uuid
  end
end
