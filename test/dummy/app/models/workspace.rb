class Workspace < ApplicationRecord
  include RecordingStudio::HasRecordingsContainer

  validates :name, presence: true
end
