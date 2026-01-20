class Workspace < ApplicationRecord
  include ControlRoom::HasRecordingsContainer

  validates :name, presence: true
end
