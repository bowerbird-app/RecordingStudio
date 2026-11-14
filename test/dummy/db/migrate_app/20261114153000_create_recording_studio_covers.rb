# frozen_string_literal: true

class CreateRecordingStudioCovers < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_covers, id: :uuid do |t|
      t.string :title, null: false
      t.integer :recordings_count, default: 0, null: false
      t.integer :events_count, default: 0, null: false
    end
  end
end
