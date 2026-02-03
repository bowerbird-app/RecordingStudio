# frozen_string_literal: true

return unless defined?(Turbo::StreamsChannel)

ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload

  actor = payload[:actor_type] ? "#{payload[:actor_type]}##{payload[:actor_id]}" : "System"
  impersonator = payload[:impersonator_type] ? "#{payload[:impersonator_type]}##{payload[:impersonator_id]}" : nil
  recordable = payload[:recordable_type] || "Recordable"
  action = payload[:action] || "updated"

  body = if impersonator
    "#{recordable} #{action} by #{actor} (impersonated by #{impersonator})"
  else
    "#{recordable} #{action} by #{actor}"
  end

  Turbo::StreamsChannel.broadcast_append_later_to(
    "recording_studio_toasts",
    target: "toast-container",
    partial: "toasts/toast",
    locals: {
      title: "Rails notification: recordings.event_created",
      body: body,
      payload: payload
    }
  )
end
