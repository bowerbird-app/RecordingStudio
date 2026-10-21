# frozen_string_literal: true

namespace :recording_studio do
  desc "Fail when app/controllers hard-code layout \"recording_studio/...\""
  task check_layouts: :environment do
    paths = RecordingStudio::Layout.hardcoded_layout_paths(Rails.root)
    next if paths.empty?

    abort <<~MESSAGE
      Hard-coded Recording Studio layout. Call recording_studio_layout on the controller instead.
      #{paths.join("\n")}
    MESSAGE
  end
end
