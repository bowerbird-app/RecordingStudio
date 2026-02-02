class AddDeviseToUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :email, from: nil, to: ""
    change_column_null :users, :email, false, ""

    add_column :users, :encrypted_password, :string, null: false, default: ""
    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_column :users, :remember_created_at, :datetime

    add_column :users, :admin, :boolean, null: false, default: false

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
  end
end