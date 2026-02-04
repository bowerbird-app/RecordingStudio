# frozen_string_literal: true

class CreateTeams < ActiveRecord::Migration[7.1]
  def change
    create_table :teams, id: :uuid do |t|
      t.string :name, null: false

      t.timestamps
    end
  end
end
