RecordingStudio.configure do |config|
  config.recordable_types = []
  config.actor = -> { Current.actor }
  config.impersonator = -> { Current.impersonator }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.recordable_dup_strategy = :dup
end

RecordingStudio.register_recordable_type("Workspace")
RecordingStudio.register_recordable_type("RecordingStudioPage")
RecordingStudio.register_recordable_type("RecordingStudioComment")
