# frozen_string_literal: true

return unless defined?(Turbo::StreamsChannel)

ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload

  actor = payload[:actor_type] ? "#{payload[:actor_type]}##{payload[:actor_id]}" : "System"
  recordable = payload[:recordable_type] || "Recordable"
  action = payload[:action] || "updated"

  Turbo::StreamsChannel.broadcast_append_later_to(
    "recording_studio_toasts",
    target: "toast-container",
    partial: "toasts/toast",
    locals: {
      title: "Rails notification: recordings.event_created",
      body: "#{recordable} #{action} by #{actor}",
      payload: payload
    }
  )
end
