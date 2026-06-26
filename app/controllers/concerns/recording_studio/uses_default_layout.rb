# frozen_string_literal: true

module RecordingStudio
  module UsesDefaultLayout
    extend ActiveSupport::Concern

    included do
      layout "recording_studio/default_layout"
      helper RecordingStudio::LayoutHelper
    end
  end
end
