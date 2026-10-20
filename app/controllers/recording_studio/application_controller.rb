# frozen_string_literal: true

module RecordingStudio
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    layout :recording_studio_layout

    private

    def recording_studio_layout
      RecordingStudio.configuration.resolved_layout(controller: self, default: "application")
    end
  end
end
