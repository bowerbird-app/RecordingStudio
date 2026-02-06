class AddCounterCachesToRecordables < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_pages, :recordings_count, :integer, default: 0, null: false
    add_column :recording_studio_pages, :events_count, :integer, default: 0, null: false
    add_column :recording_studio_comments, :recordings_count, :integer, default: 0, null: false
    add_column :recording_studio_comments, :events_count, :integer, default: 0, null: false
  end
end
