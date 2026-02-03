class AddImpersonatorToRecordingStudioEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_events, :impersonator_type, :string
    add_column :recording_studio_events, :impersonator_id, :uuid
  end
end
