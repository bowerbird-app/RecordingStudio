class RecordingStudioComment < ApplicationRecord
  validates :body, presence: true

  def self.recordable_type_label
    "Comment"
  end

  class << self
    alias_method :recording_studio_type_label, :recordable_type_label
  end

  def recordable_name
    snippet = body.to_s.squish.presence
    snippet.present? ? "Comment: #{snippet.truncate(60)}" : self.class.recordable_type_label
  end

  alias_method :recording_studio_label, :recordable_name
end
