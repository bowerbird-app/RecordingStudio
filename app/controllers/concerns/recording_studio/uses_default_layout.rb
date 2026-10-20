# frozen_string_literal: true

module RecordingStudio
  module UsesDefaultLayout
    extend ActiveSupport::Concern

    included do
      layout :recording_studio_configured_layout
      helper RecordingStudio::LayoutHelper
    end

    def recording_studio_configured_layout
      RecordingStudio.configuration.resolved_layout(
        controller: self,
        default: "recording_studio/default_layout"
      )
    end
  end
end
