# frozen_string_literal: true

require "recording_studio/version"
require "recording_studio/engine"
require "recording_studio/configuration"
require "recording_studio/counter_caches"
require "recording_studio/delegated_type_registrar"
require "recording_studio/duplication"
require "recording_studio/errors"
require "recording_studio/identity"
require "recording_studio/labels"
require "recording_studio/recordable"
require "recording_studio/relationships"
require "recording_studio/services/base_service"
require "recording_studio/services/example_service"

# rubocop:disable Metrics/ModuleLength, Metrics/ClassLength

module RecordingStudio
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def registered_capabilities
      @registered_capabilities ||= {}
    end

    def register_capability(name, mod)
      capability_mutex.synchronize do
        registered_capabilities[name.to_sym] = { mod: mod }
      end
      apply_capabilities! if defined?(RecordingStudio::Recording)
    end

    def apply_capabilities!
      capability_mutex.synchronize do
        registered_capabilities.each_value do |registration|
          mod = registration.fetch(:mod)
          next if RecordingStudio::Recording.included_modules.include?(mod)

          RecordingStudio::Recording.include(mod)
        end
      end
    end

    def register_recordable_type(name)
      type_name = recordable_type_name(name)
      raise ArgumentError, "recordable type is required" if type_name.blank?

      configuration.recordable_types = (configuration.recordable_types + [type_name]).uniq
      RecordingStudio::DelegatedTypeRegistrar.apply!
    end

    def recordable_type_name(recordable_or_type)
      RecordingStudio::Identity.type_name_for(recordable_or_type)
    end

    def resolve_recordable_type(recordable_or_type)
      RecordingStudio::Identity.resolve_type(recordable_or_type)
    end

    def recordable_identifier(recordable)
      RecordingStudio::Identity.identifier_for(recordable)
    end

    def recordable_global_id(recordable)
      RecordingStudio::Identity.global_id_for(recordable)
    end

    def root_recording_or_self(recording)
      RecordingStudio::Relationships.root_recording_or_self(recording)
    end

    def root_recording_id_for(recording)
      RecordingStudio::Relationships.root_recording_id_for(recording)
    end

    def root_recording?(recording)
      RecordingStudio::Relationships.root_recording?(recording)
    end

    def assert_recording_belongs_to_root!(root_recording, recording, **)
      RecordingStudio::Relationships.assert_recording_belongs_to_root!(root_recording, recording, **)
    end

    def assert_root_recording!(recording, **)
      RecordingStudio::Relationships.assert_root_recording!(recording, **)
    end

    def assert_parent_recording_belongs_to_root!(parent_recording, root_recording, **)
      RecordingStudio::Relationships.assert_parent_recording_belongs_to_root!(
        parent_recording,
        root_recording,
        **
      )
    end

    def update_polymorphic_counter(recordable_or_type, recordable_id, column, delta)
      RecordingStudio::CounterCaches.change_polymorphic_counter(recordable_or_type, recordable_id, column, delta)
    end

    def dup_strategy_for(recordable_or_type)
      configuration.recordable_dup_strategy_for(recordable_or_type)
    end

    def duplicate_recordable(recordable)
      RecordingStudio::Duplication.duplicate_recordable(recordable)
    end

    def enable_capability(capability, on:)
      configuration.enable_capability(capability, on: on)
    end

    def set_capability_options(capability, on:, **)
      configuration.set_capability_options(capability, on: on, **)
    end

    def capability_options(capability, for_type:)
      configuration.capability_options(capability, for_type: for_type)
    end

    def record!(action:, recordable:, recording: nil, root_recording: nil, actor: nil, impersonator: nil,
                metadata: {}, occurred_at: Time.current, idempotency_key: nil, parent_recording: nil)
      RecordingStudio::DelegatedTypeRegistrar.apply!
      root_recording ||= root_recording_or_self(recording)
      raise ArgumentError, "root_recording is required" if root_recording.nil?
      assert_root_recording!(root_recording)

      assert_recording_belongs_to_root!(
        root_recording,
        recording,
        message: "recording must belong to the provided root_recording"
      )

      assert_parent_recording_belongs_to_root!(parent_recording, root_recording)

      resolved_actor = actor || configuration.actor&.call
      resolved_impersonator = impersonator || configuration.impersonator&.call
      metadata = metadata.presence || {}
      idempotency_key = idempotency_key.presence

      RecordingStudio::Recording.transaction do
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
          recording = RecordingStudio::Recording.create!(
            root_recording: root_recording,
            recordable: recordable,
            parent_recording: parent_recording
          )
          previous_recordable = nil
        end

        event = recording.events.create!(
          action: action,
          recordable: recordable,
          previous_recordable: previous_recordable,
          actor: resolved_actor,
          impersonator: resolved_impersonator,
          occurred_at: occurred_at,
          metadata: metadata,
          idempotency_key: idempotency_key
        )

        instrument_event(event)
        event
      end
    end

    private

    def capability_mutex
      @capability_mutex ||= Mutex.new
    end

    def find_idempotent_event(recording, idempotency_key)
      return unless recording&.persisted? && idempotency_key

      recording.events.find_by(idempotency_key: idempotency_key)
    end

    def handle_idempotency(event)
      return unless event

      case configuration.idempotency_mode.to_sym
      when :raise
        masked_key = event.idempotency_key.to_s
        masked_key = masked_key.length <= 4 ? "****" : "****#{masked_key[-4, 4]}"
        raise IdempotencyError, "Event already exists for idempotency key (masked): #{masked_key}"
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
        root_recording_id: event.recording.root_recording_id,
        action: event.action,
        recordable_type: event.recordable_type,
        recordable_id: event.recordable_id,
        previous_recordable_type: event.previous_recordable_type,
        previous_recordable_id: event.previous_recordable_id,
        actor_type: event.actor_type,
        actor_id: event.actor_id,
        impersonator_type: event.impersonator_type,
        impersonator_id: event.impersonator_id,
        occurred_at: event.occurred_at
      )
    end
  end
end

require "recording_studio/capability"
# rubocop:enable Metrics/ModuleLength, Metrics/ClassLength
