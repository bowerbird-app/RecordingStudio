# frozen_string_literal: true

class CreatePages < ActiveRecord::Migration[7.1]
  def change
    create_table :recording_studio_pages, id: :uuid do |t|
      t.text :summary
      t.string :title, null: false
    end
  end
end
