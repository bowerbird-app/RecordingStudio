class RecordingStudioPage < ApplicationRecord
  validates :title, presence: true

  include Capabilities::Commentable.with(comment_class: "RecordingStudioComment")
  include RecordingStudio::Capabilities::Movable.to("RecordingStudioFolder", "Workspace")
  include RecordingStudio::Capabilities::Copyable.to("RecordingStudioFolder", "Workspace")
end
