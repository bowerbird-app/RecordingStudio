class AddImpersonatorToRecordingStudioEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_events, :impersonator_type, :string unless column_exists?(:recording_studio_events, :impersonator_type)
    add_column :recording_studio_events, :impersonator_id, :uuid unless column_exists?(:recording_studio_events, :impersonator_id)
  end
end
