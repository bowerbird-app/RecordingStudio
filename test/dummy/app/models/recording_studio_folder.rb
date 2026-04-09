class RecordingStudioFolder < ApplicationRecord
  validates :name, presence: true

  include RecordingStudio::Capabilities::Copyable.to("RecordingStudioFolder", "Workspace")

  def self.recording_studio_type_label
    "Folder"
  end

  def recording_studio_label
    label = name.to_s.squish.presence || self.class.recording_studio_type_label
    "📁 #{label}"
  end
end
