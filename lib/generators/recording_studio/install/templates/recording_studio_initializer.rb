# frozen_string_literal: true

RecordingStudio.configure do |config|
  # Registered delegated_type recordables (strings or classes)
  config.recordable_types = []

  # Actor resolver for events when no actor is explicitly supplied
  config.actor = -> { Current.actor }

  # Emit ActiveSupport::Notifications events
  config.event_notifications_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Include child recordings by default when trashing/restoring
  config.include_children = false

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup
end

# Example recordable registration
RecordingStudio.register_recordable_type("Page")
