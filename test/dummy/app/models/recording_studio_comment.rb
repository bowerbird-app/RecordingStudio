class RecordingStudioComment < ApplicationRecord
  validates :body, presence: true

  def self.recording_studio_type_label
    "Comment"
  end

  def recording_studio_label
    snippet = body.to_s.squish.presence
    snippet.present? ? "Comment: #{snippet.truncate(60)}" : self.class.recording_studio_type_label
  end
end
