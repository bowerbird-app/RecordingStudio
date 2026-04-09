class RecordingStudioFolder < ApplicationRecord
  validates :name, presence: true

  include RecordingStudio::Capabilities::Copyable.to(
    deep_copy: { include: %w[RecordingStudioFolder RecordingStudioPage] }
  )
end
