# frozen_string_literal: true

require "control_room/version"
require "control_room/engine"
require "control_room/configuration"
require "control_room/delegated_type_registrar"
require "control_room/errors"
require "control_room/services/base_service"
require "control_room/services/example_service"

module ControlRoom
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def register_recordable_type(name)
      type_name = name.is_a?(Class) ? name.name : name.to_s
      configuration.recordable_types = (configuration.recordable_types + [type_name]).uniq
      ControlRoom::DelegatedTypeRegistrar.apply!
    end

    def record!(action:, recordable:, recording: nil, container: nil, actor: nil,
                metadata: {}, occurred_at: Time.current, idempotency_key: nil)
      ControlRoom::DelegatedTypeRegistrar.apply!
      container ||= recording&.container
      raise ArgumentError, "container is required" if container.nil?

      resolved_actor = actor || configuration.actor_provider&.call
      metadata = metadata.presence || {}
      idempotency_key = idempotency_key.presence

      ControlRoom::Recording.transaction do
        existing_event = find_idempotent_event(recording, idempotency_key)
        return handle_idempotency(existing_event) if existing_event

        recordable.save! unless recordable.persisted?
        if recording
          previous_recordable = recording.recordable
          if previous_recordable && previous_recordable.class.name != recordable.class.name
            raise ArgumentError, "recordable type must remain #{previous_recordable.class.name}"
          end
          recording.update!(recordable: recordable) if recordable != previous_recordable
        else
          recording = ControlRoom::Recording.create!(container: container, recordable: recordable)
          previous_recordable = nil
        end

        event = recording.events.create!(
          action: action,
          recordable: recordable,
          previous_recordable: previous_recordable,
          actor: resolved_actor,
          occurred_at: occurred_at,
          metadata: metadata,
          idempotency_key: idempotency_key
        )

        instrument_event(event)
        event
      end
    end

    private

    def find_idempotent_event(recording, idempotency_key)
      return unless recording&.persisted? && idempotency_key

      recording.events.find_by(idempotency_key: idempotency_key)
    end

    def handle_idempotency(event)
      return unless event

      case configuration.idempotency_mode.to_sym
      when :return_existing
        event
      when :raise
        raise IdempotencyError, "Event already exists for idempotency key #{event.idempotency_key}"
      else
        event
      end
    end

    def instrument_event(event)
      return unless configuration.event_notifications_enabled

      ActiveSupport::Notifications.instrument(
        "recordings.event_created",
        schema_version: 1,
        event_id: event.id,
        recording_id: event.recording_id,
        container_type: event.recording.container_type,
        container_id: event.recording.container_id,
        action: event.action,
        recordable_type: event.recordable_type,
        recordable_id: event.recordable_id,
        previous_recordable_type: event.previous_recordable_type,
        previous_recordable_id: event.previous_recordable_id,
        actor_type: event.actor_type,
        actor_id: event.actor_id,
        occurred_at: event.occurred_at
      )
    end
  end
end
