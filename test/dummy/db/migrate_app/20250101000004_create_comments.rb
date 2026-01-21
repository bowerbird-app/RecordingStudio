# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[7.1]
  def change
    create_table :comments, id: :uuid do |t|
      t.text :body, null: false
      t.uuid :original_id
      t.integer :version, null: false, default: 1

      t.timestamps
    end

    add_index :comments, :original_id
  end
end
