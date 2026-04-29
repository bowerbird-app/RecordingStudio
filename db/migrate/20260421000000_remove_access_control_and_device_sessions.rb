# frozen_string_literal: true

class RemoveAccessControlAndDeviceSessions < ActiveRecord::Migration[8.1]
  def up
    remove_index :recording_studio_recordings, name: "idx_rs_recordings_root_access", if_exists: true
    remove_index :recording_studio_recordings,
                 name: "index_rs_unique_active_access_boundary_per_parent",
                 if_exists: true

    drop_table :recording_studio_device_sessions, if_exists: true
    drop_table :recording_studio_access_boundaries, if_exists: true
    drop_table :recording_studio_accesses, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "access control and device session features were removed from core"
  end
end
