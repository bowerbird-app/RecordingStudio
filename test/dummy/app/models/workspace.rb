class Workspace < ApplicationRecord
  self.table_name = "recording_studio_workspaces"

  validates :name, presence: true
end
