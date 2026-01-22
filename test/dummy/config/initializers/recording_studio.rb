RecordingStudio.configure do |config|
  config.recordable_types = []
  config.actor_provider = -> { Current.actor }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.unrecord_mode = :soft
  config.recordable_dup_strategy = :dup
  config.cascade_unrecord = ->(recording) { recording.child_recordings.with_archived }
end

RecordingStudio.register_recordable_type("Page")
RecordingStudio.register_recordable_type("Comment")
