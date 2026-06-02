class RecordingStudioPage < ApplicationRecord
  recording_studio_recordable label: "Page", root: false,
                              allowed_parent_types: ["Workspace", "RecordingStudioFolder", "RecordingStudioPage"]

  validates :title, presence: true

  include Capabilities::Commentable.with(comment_class: "RecordingStudioComment")

  def self.recordable_type_label
    "Page"
  end

  class << self
    alias_method :recording_studio_type_label, :recordable_type_label
  end
end
