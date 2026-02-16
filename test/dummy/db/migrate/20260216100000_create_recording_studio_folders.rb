class CreateRecordingStudioFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_folders, id: :uuid do |t|
      t.string :name, null: false
      t.integer :recordings_count, default: 0, null: false
      t.integer :events_count, default: 0, null: false
    end
  end
end
