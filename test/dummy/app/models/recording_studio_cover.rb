# frozen_string_literal: true

class RecordingStudioCover < ApplicationRecord
  recording_studio_recordable label: "Cover",
                              root: false,
                              allowed_parent_types: %w[Workspace RecordingStudioPage],
                              one_per_parent: true

  validates :title, presence: true
end
