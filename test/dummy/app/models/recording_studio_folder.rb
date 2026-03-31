class RecordingStudioFolder < ApplicationRecord
  validates :name, presence: true

  include RecordingStudio::Capabilities::Copyable.to("RecordingStudioFolder", "Workspace")
end
