class RecordingStudioPage < ApplicationRecord
  validates :title, presence: true

  include Capabilities::Commentable.with(comment_class: "RecordingStudioComment")
  include RecordingStudio::Capabilities::Copyable.to("RecordingStudioFolder", "Workspace")

  def self.recording_studio_type_label
    "Page"
  end
end
