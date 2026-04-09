class RecordingStudioPage < ApplicationRecord
  validates :title, presence: true

  include Capabilities::Commentable.with(comment_class: "RecordingStudioComment")
  include RecordingStudio::Capabilities::Copyable.to("RecordingStudioFolder", "Workspace")

  def self.recordable_type_label
    "Page"
  end

  class << self
    alias_method :recording_studio_type_label, :recordable_type_label
  end
end
