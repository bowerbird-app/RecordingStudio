class RenameServiceAccountsToSystemActors < ActiveRecord::Migration[8.1]
  def change
    rename_table :service_accounts, :system_actors
  end
end
