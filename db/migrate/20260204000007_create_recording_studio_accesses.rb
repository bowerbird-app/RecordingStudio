# frozen_string_literal: true

class CreateRecordingStudioAccesses < ActiveRecord::Migration[7.1]
  def change
    create_table :recording_studio_accesses, id: :uuid do |t|
      t.string :grantee_type, null: false
      t.uuid :grantee_id, null: false
      t.string :access_level, null: false, default: "view"

      t.timestamps
    end

    add_index :recording_studio_accesses, %i[grantee_type grantee_id],
              name: "index_recording_studio_accesses_on_grantee"
  end
end
