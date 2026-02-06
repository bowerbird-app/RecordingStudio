# frozen_string_literal: true

class CreateRecordingStudioComments < ActiveRecord::Migration[7.1]
  def change
    create_table :recording_studio_comments, id: :uuid do |t|
      t.text :body, null: false
    end
  end
end
