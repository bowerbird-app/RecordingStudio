ControlRoom.configure do |config|
  config.recordable_types = []
  config.actor_provider = -> { Current.actor }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.unrecord_mode = :soft
  config.recordable_dup_strategy = :dup
end

ControlRoom.register_recordable_type("Page")
ControlRoom.register_recordable_type("Comment")
