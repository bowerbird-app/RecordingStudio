# frozen_string_literal: true

require "recording_studio/capabilities/trashable"

module RecordingStudio
  module Addons
    module Trashable
      class << self
        def load!
          mod = RecordingStudio::Capabilities::Trashable::RecordingMethods
          registered_mod = RecordingStudio.registered_capabilities.dig(:trashable, :mod)
          return if registered_mod == mod

          RecordingStudio.register_capability(:trashable, mod)
        end
      end
    end
  end
end

RecordingStudio::Addons::Trashable.load!

if defined?(Rails) && Rails.application
  Rails.application.config.to_prepare do
    RecordingStudio::Addons::Trashable.load!
  end
end
