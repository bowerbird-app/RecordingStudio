class AddCounterCachesToRecordables < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :recordings_count, :integer, default: 0, null: false
    add_column :pages, :events_count, :integer, default: 0, null: false
    add_column :comments, :recordings_count, :integer, default: 0, null: false
    add_column :comments, :events_count, :integer, default: 0, null: false
  end
end
