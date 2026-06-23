# Ensure the dummy app renders RecordingStudio pages with the shared default layout contract.
Rails.application.config.to_prepare do
  RecordingStudio::ApplicationController.include(RecordingStudio::UsesDefaultLayout)
end
