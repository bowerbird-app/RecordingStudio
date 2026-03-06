# frozen_string_literal: true

require "recording_studio/version"
require "recording_studio/engine"
require "recording_studio/configuration"
require "recording_studio/delegated_type_registrar"
require "recording_studio/errors"
require "recording_studio/recordable"
require "recording_studio/services/base_service"
require "recording_studio/services/example_service"
require "recording_studio/services/access_check_class_methods"
require "recording_studio/services/access_check"
require "recording_studio/services/root_recording_resolver"
require "recording_studio/concerns/device_session_concern"

# rubocop:disable Metrics/ModuleLength, Metrics/ClassLength
module RecordingStudio
  LEGACY_FEATURE_ADDONS = {
    move: { gem_name: "recording-studio-move", constant_paths: %w[RecordingStudio::Move] },
    copyable: { gem_name: "recording-studio-copy", constant_paths: %w[RecordingStudio::Copy] },
    device_sessions: {
      gem_name: "recording-studio-device-sessions",
      constant_paths: %w[RecordingStudio::DeviceSessions]
    }
  }.freeze

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def features
      configuration.features
    end

    def registered_capabilities
      @registered_capabilities ||= {}
    end

    def register_capability(name, mod, legacy_feature_gate: nil)
      registered_capabilities[name.to_sym] = {
        mod: mod,
        legacy_feature_gate: legacy_feature_gate&.to_sym
      }
      apply_capabilities! if defined?(RecordingStudio::Recording)
    end

    def apply_capabilities!
      registered_capabilities.each_value do |registration|
        mod = registration.fetch(:mod)
        legacy_feature_gate = registration[:legacy_feature_gate]
        next if legacy_feature_gate && !legacy_feature_enabled?(legacy_feature_gate)
        next if RecordingStudio::Recording.included_modules.include?(mod)

        RecordingStudio::Recording.include(mod)
      end
    end

    def register_recordable_type(name)
      type_name = name.is_a?(Class) ? name.name : name.to_s
      configuration.recordable_types = (configuration.recordable_types + [type_name]).uniq
      RecordingStudio::DelegatedTypeRegistrar.apply!
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
      root_recording ||= recording&.root_recording
      raise ArgumentError, "root_recording is required" if root_recording.nil?
      if recording && recording.root_recording_id != root_recording.id
        raise ArgumentError, "recording must belong to the provided root_recording"
      end

      assert_parent_recording_root!(parent_recording, root_recording)

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

    def warn_legacy_feature_use!(feature_key, used_by:)
      return unless legacy_feature_enabled?(feature_key)
      return if warned_once?([:feature_use, feature_key])

      emit_warning(
        "[RecordingStudio] Legacy built-in '#{feature_key}' feature is enabled and used via #{used_by}. " \
        "For addon migration, disable it in your initializer:\n#{feature_disable_snippet(feature_key)}"
      )
    end

    def warn_legacy_addon_conflicts!
      LEGACY_FEATURE_ADDONS.each do |feature_key, addon|
        next unless legacy_feature_enabled?(feature_key)
        next unless addon_loaded?(addon)
        next if warned_once?([:addon_conflict, feature_key])

        emit_warning(
          "[RecordingStudio] Detected #{addon[:gem_name]} while built-in '#{feature_key}' is enabled. " \
          "Disable the built-in feature to avoid conflicts:\n#{feature_disable_snippet(feature_key)}"
        )
      end
    end

    def reset_runtime_warnings!
      @runtime_warnings = Set.new
    end

    private

    def legacy_feature_enabled?(feature_key)
      features.public_send("#{feature_key}?")
    end

    def addon_loaded?(addon)
      gem_loaded = Gem.loaded_specs.key?(addon.fetch(:gem_name))
      constant_loaded = addon.fetch(:constant_paths, []).any? { |path| constant_defined_path?(path) }
      gem_loaded || constant_loaded
    end

    def constant_defined_path?(path)
      path.split("::").reject(&:empty?).inject(Object) do |scope, const_name|
        return false unless scope.const_defined?(const_name, false)

        scope.const_get(const_name, false)
      end
      true
    rescue NameError
      false
    end

    def warned_once?(key)
      @runtime_warnings ||= Set.new
      already_warned = @runtime_warnings.include?(key)
      @runtime_warnings << key
      already_warned
    end

    def emit_warning(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
    end

    def feature_disable_snippet(feature_key)
      "RecordingStudio.configure do |config|\n  config.features.#{feature_key} = false\nend"
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

    def assert_parent_recording_root!(parent_recording, root_recording)
      return unless parent_recording
      return if parent_recording.root_recording_id == root_recording.id

      raise ArgumentError, "parent_recording must belong to the provided root_recording"
    end
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/ClassLength

require "recording_studio/capability"
require "recording_studio/capabilities/movable"
require "recording_studio/capabilities/copyable"
