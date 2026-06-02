# frozen_string_literal: true

RecordingStudio.configure do |config|
  # Registered delegated_type recordables (strings or classes)
  config.recordable_types = []

  # Require each configured ActiveRecord type to call recording_studio_recordable.
  # Set false only during migrations from older apps; missing declarations warn.
  config.require_recordable_declarations = true

  # Actor resolver for events when no actor is explicitly supplied
  config.actor = -> { Current.actor }

  # Emit ActiveSupport::Notifications events
  config.event_notifications_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup

  # Optional per-type duplication overrides for trusted addon code
  # config.register_recordable_dup_strategy("Page") { |recordable| Page.new(title: recordable.title) }
end

# Example recordable registration, after the model declaration below exists:
# RecordingStudio.register_recordable_type("Page")

# In app/models/page.rb:
# class Page < ApplicationRecord
#   recording_studio_recordable label: "Page", root: true
# end

# Optional label/presentation overrides for trusted addon code
# RecordingStudio::Labels.register_formatter("Page", name: ->(page) { page.title })
