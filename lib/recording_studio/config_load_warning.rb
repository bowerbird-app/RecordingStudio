# frozen_string_literal: true

module RecordingStudio
  module ConfigLoadWarning
    def self.call(source, error)
      RecordingStudio::Warnings.warn(
        "[RecordingStudio] Could not #{source} (#{error.class}: #{error.message})"
      )
    end

    def self.yaml_for(app)
      return unless Rails.root.join("config/recording_studio.yml").exist?

      app.config_for(:recording_studio)
    rescue StandardError => e
      call("load config_for(:recording_studio)", e)
      nil
    end
  end
end
