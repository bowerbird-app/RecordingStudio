# frozen_string_literal: true

ControlRoom.configure do |config|
  # Registered delegated_type recordables (strings or classes)
  config.recordable_types = []

  # Actor provider for events when no actor is explicitly supplied
  config.actor_provider = -> { Current.actor }

  # Emit ActiveSupport::Notifications events
  config.instrumentation_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Unrecording behavior
  config.unrecord_mode = :soft # or :hard

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup
end

# Example recordable registration
ControlRoom.register_recordable_type("Page")
