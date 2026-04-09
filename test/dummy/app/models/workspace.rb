class Workspace < ApplicationRecord
  self.table_name = "recording_studio_workspaces"

  validates :name, presence: true

  def self.recording_studio_type_label
    "Workspace"
  end

  def recording_studio_label
    name.to_s.squish.presence || self.class.recording_studio_type_label
  end
end
