class RecordingStudioFolder < ApplicationRecord
  validates :name, presence: true

  def self.recordable_type_label
    "Folder"
  end

  class << self
    alias_method :recording_studio_type_label, :recordable_type_label
  end

  def recordable_name
    label = name.to_s.squish.presence || self.class.recordable_type_label
    "📁 #{label}"
  end

  alias_method :recording_studio_label, :recordable_name
end
