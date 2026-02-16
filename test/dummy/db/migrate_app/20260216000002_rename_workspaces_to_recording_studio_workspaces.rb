class RenameWorkspacesToRecordingStudioWorkspaces < ActiveRecord::Migration[8.1]
  def up
    rename_table :workspaces, :recording_studio_workspaces
    remove_column :recording_studio_workspaces, :updated_at, :datetime
  end

  def down
    add_column :recording_studio_workspaces, :updated_at, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }
    rename_table :recording_studio_workspaces, :workspaces
  end
end
