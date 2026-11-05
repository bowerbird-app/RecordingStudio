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

  # Writes fail closed. Missing authorize_write raises AuthorizationError.
  # Missing actor raises ActorRequired. Return truthy to allow the write.
  # The callable also receives action:, recordable:, recording:, root_recording:,
  # parent_recording:, and impersonator:.
  config.authorize_write = ->(actor:, **) { actor.present? }

  # Set true only to restore the old fail-open writes (no authorizer, no actor).
  # config.allow_unauthorized_writes = false

  # Still used when allow_unauthorized_writes is true. Redundant with the new default.
  # config.require_actor = true

  # Reject oversized event metadata payloads (JSON byte size)
  # config.max_metadata_bytes = 16_384

  # Allow Relation/Arel/proc recordable query escape hatches (trusted host code only)
  # config.allow_unsafe_recordable_queries = false

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup

  # Optional per-type duplication overrides for trusted addon code
  # config.register_recordable_dup_strategy("Page") { |recordable| Page.new(title: recordable.title) }

  # Application name used as title fallback in default layout (defaults to "RecordingStudio")
  # config.app_name = "My App"
end

# Example recordable registration, after the model declarations below exist:
# RecordingStudio.register_recordable_type("Workspace")
# RecordingStudio.register_recordable_type("Page")

# In app/models/workspace.rb:
# class Workspace < ApplicationRecord
#   recording_studio_recordable label: "Workspace", root: true
# end
#
# class MessagesRoot < ApplicationRecord
#   recording_studio_recordable label: "Messages", root: true, shared: true
# end

# In app/models/page.rb:
# class Page < ApplicationRecord
#   recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
# end

# Optional label/presentation overrides for trusted addon code
# RecordingStudio::Labels.register_formatter("Page", name: ->(page) { page.title })
