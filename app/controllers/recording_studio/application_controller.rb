# frozen_string_literal: true

module RecordingStudio
  class ApplicationController < ActionController::Base
    include ControllerLayout

    protect_from_forgery with: :exception

    recording_studio_layout
  end
end
