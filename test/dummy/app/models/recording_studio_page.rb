class RecordingStudioPage < ApplicationRecord
  validates :title, presence: true

  include RecordingStudio::Capabilities::Trashable.with
  include Capabilities::Commentable.with(comment_class: "RecordingStudioComment")

  def self.recordable_type_label
    "Page"
  end

  class << self
    alias_method :recording_studio_type_label, :recordable_type_label
  end
end
