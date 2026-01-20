class CreateDummyRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces, id: :uuid do |t|
      t.string :name, null: false

      t.timestamps
    end

    create_table :users, id: :uuid do |t|
      t.string :name, null: false
      t.string :email

      t.timestamps
    end

    create_table :service_accounts, id: :uuid do |t|
      t.string :name, null: false

      t.timestamps
    end

    create_table :pages, id: :uuid do |t|
      t.string :title, null: false
      t.text :summary
      t.integer :version, null: false, default: 1
      t.uuid :original_id

      t.timestamps
    end

    add_index :pages, :original_id
  end
end
