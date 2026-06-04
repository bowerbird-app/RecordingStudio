# frozen_string_literal: true

require "monitor"
require "recording_studio/version"
require "recording_studio/engine"
require "recording_studio/configuration"
require "recording_studio/counter_caches"
require "recording_studio/errors"
require "recording_studio/delegated_type_registrar"
require "recording_studio/duplication"
require "recording_studio/identity"
require "recording_studio/labels"
require "recording_studio/recordable"
require "recording_studio/recordable_declarations"
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

    def synchronize_capabilities(&block)
      capability_mutex.synchronize(&block)
    end

    def register_capability(name, mod = nil, recording_methods: nil, source: nil, child_recordables: [])
      capability_name = normalize_capability_name(name)
      normalized_recording_methods = normalize_capability_recording_methods!(recording_methods || mod)
      normalized_source = normalize_capability_source(source)
      normalized_children = normalize_capability_child_recordables(child_recordables)
      if normalized_children.any? && normalized_source.blank?
        raise ArgumentError, "source is required when child_recordables are present"
      end

      capability_mutex.synchronize do
        merge_capability_registration!(
          capability_name,
          normalized_recording_methods,
          recording_methods: normalized_recording_methods,
          source: normalized_source,
          child_recordables: normalized_children
        )
      end
      apply_capabilities! if defined?(RecordingStudio::Recording) && normalized_recording_methods
    end

    def apply_capabilities!
      capability_mutex.synchronize do
        registered_capabilities.each_value do |registration|
          mod = registration[:recording_methods] || registration[:mod]
          next unless mod
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

    def recordable_name(recordable)
      RecordingStudio::Labels.name_for(recordable)
    end

    def recordable_type_label(recordable_or_type)
      RecordingStudio::Labels.type_label_for(recordable_or_type)
    end

    def recordable_type_plural_label(recordable_or_type)
      RecordingStudio::Labels.type_plural_label_for(recordable_or_type)
    end

    def recordable_declaration_for(recordable_or_type)
      RecordingStudio::RecordableDeclarations.declaration_for(recordable_or_type)
    end

    def recordable_declaration_defined?(recordable_or_type)
      RecordingStudio::RecordableDeclarations.declaration_defined?(recordable_or_type)
    end

    def recordable_declarations
      RecordingStudio::RecordableDeclarations.ensure_loaded!
      RecordingStudio::RecordableDeclarations.declarations.dup
    end

    def validate_recordable_declarations! # rubocop:disable Naming/PredicateMethod
      RecordingStudio::RecordableDeclarations.enforce_configuration!
      true
    end

    def declared_parent_types_for(recordable_or_type)
      RecordingStudio::RecordableDeclarations.declared_parent_types_for(recordable_or_type)
    end

    def declared_allowed_parent_types_for(recordable_or_type)
      declared_parent_types_for(recordable_or_type)
    end

    def allowed_parent_types_for(recordable_or_type)
      RecordingStudio::RecordableDeclarations.allowed_parent_types_for(recordable_or_type)
    end

    def capability_child_recordables_for(capability)
      capability_name = normalize_capability_name(capability)
      capability_mutex.synchronize do
        registered_capabilities.fetch(capability_name, {}).fetch(:child_recordables, []).dup.freeze
      end
    end

    def capability_parent_types_for(recordable_or_type)
      type_name = recordable_type_name(recordable_or_type)
      return [].freeze if type_name.blank?

      configuration.capability_parent_types_for(type_name).dup.freeze
    end

    def capability_allowed_parent_types_for(recordable_or_type)
      capability_parent_types_for(recordable_or_type)
    end

    def recordable_parent_allowances_for(recordable_or_type)
      type_name = recordable_type_name(recordable_or_type)
      return {}.freeze if type_name.blank?

      capability_mutex.synchronize do
        capabilities_by_type = configuration.instance_variable_get(:@capabilities) || {}

        registered_capabilities.each_with_object({}) do |(capability_name, registration), result|
          next unless Array(registration[:child_recordables]).include?(type_name)

          source = registration[:source]
          next if source.blank?

          result[source] ||= Set.new
          capabilities_by_type.each do |parent_type_name, capability_names|
            result[source] << parent_type_name if capability_names.include?(capability_name)
          end
        end.each_with_object({}) do |(source, parents), result|
          result[source] = parents.to_a.sort.freeze
        end.freeze
      end
    end

    def child_recordable_types_for(recordable_or_type)
      configuration.child_recordable_types_for(recordable_or_type)
    end

    def parent_capabilities_for(child_type:, parent_recording: nil, parent_type: nil)
      resolved_parent_type = parent_type || parent_recording&.recordable_type
      configuration.parent_capabilities_for(child_type: child_type, parent_type: resolved_parent_type)
    end

    def root_allowed?(recordable_or_type)
      RecordingStudio::RecordableDeclarations.root_allowed?(recordable_or_type)
    end

    def root_recordable_type?(recordable_or_type)
      root_allowed?(recordable_or_type)
    end

    def root_recordable_types
      RecordingStudio::RecordableDeclarations.root_recordable_types
    end

    def root_recordable_declarations
      RecordingStudio::RecordableDeclarations.declarations_for_configured_types.select(&:root?)
    end

    def parent_allowed?(child_type:, parent_recording:)
      RecordingStudio::RecordableDeclarations.parent_allowed?(
        child_type: child_type,
        parent_recording: parent_recording
      )
    end

    def assert_root_allowed!(recordable_or_type)
      RecordingStudio::RecordableDeclarations.assert_root_allowed!(recordable_or_type)
    end

    def assert_parent_allowed!(child_type:, parent_recording:)
      RecordingStudio::RecordableDeclarations.assert_parent_allowed!(
        child_type: child_type,
        parent_recording: parent_recording
      )
    end

    def root_recording_for(recordable)
      raise ArgumentError, "recordable is required" if recordable.nil?

      unless recordable.respond_to?(:persisted?) && recordable.persisted?
        raise ArgumentError, "recordable must be persisted"
      end

      assert_root_allowed!(recordable)

      RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: recordable, parent_recording_id: nil)
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
      capability_name = normalize_capability_name(capability)
      type_name = recordable_type_name(on)
      raise ArgumentError, "recordable type is required" if type_name.blank?

      capability_mutex.synchronize do
        configuration.enable_capability(capability_name, on: type_name)
      end
    end

    def capability_enabled?(capability, **kwargs)
      resolved_type = kwargs.fetch(:for)
      configuration.capability_enabled?(capability, for_type: resolved_type)
    end

    def capabilities_for(recordable_or_type)
      configuration.capabilities_for(recordable_or_type)
    end

    def set_capability_options(capability, on:, **)
      configuration.set_capability_options(capability, on: on, **)
    end

    def capability_options(capability, **kwargs)
      resolved_type = kwargs[:for] || kwargs[:for_type]
      configuration.capability_options(capability, for_type: resolved_type)
    end

    def record!(action:, recordable:, recording: nil, root_recording: nil, actor: nil, impersonator: nil,
                metadata: {}, occurred_at: Time.current, idempotency_key: nil, parent_recording: nil)
      RecordingStudio::DelegatedTypeRegistrar.apply!
      raise ArgumentError, "root_recording is required" if root_recording.nil? && recording.nil?

      resolved_actor = actor || configuration.actor&.call
      resolved_impersonator = impersonator || configuration.impersonator&.call
      metadata = metadata.presence || {}
      idempotency_key = idempotency_key.presence

      RecordingStudio::Recording.transaction do
        recording = reload_recording_for_hierarchy!(recording, :recording) if recording
        root_recording ||= root_recording_or_self(recording)
        raise ArgumentError, "root_recording is required" if root_recording.nil?

        root_recording = reload_recording_for_hierarchy!(root_recording, :root_recording)
        parent_recording = reload_recording_for_hierarchy!(parent_recording, :parent_recording) if parent_recording

        assert_root_recording!(root_recording)

        assert_recording_belongs_to_root!(
          root_recording,
          recording,
          message: "recording must belong to the provided root_recording"
        )

        assert_parent_recording_belongs_to_root!(parent_recording, root_recording)

        existing_event = find_idempotent_event(recording, idempotency_key)
        return handle_idempotency(existing_event) if existing_event

        unless recording
          if parent_recording.nil?
            assert_root_allowed!(recordable.class.name)
            raise RecordingStudio::OrphanRecording,
                  "#{recordable.class.name} cannot be recorded under an existing root without a parent; " \
                  "use root_recording_for to create root recordings"
          else
            assert_parent_allowed!(child_type: recordable.class.name, parent_recording: parent_recording)
          end
        end

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
      @capability_mutex ||= Monitor.new
    end

    def merge_capability_registration!(capability_name, mod, recording_methods:, source:, child_recordables:)
      existing = registered_capabilities[capability_name]

      unless existing
        return registered_capabilities[capability_name] = {
          mod: mod,
          recording_methods: recording_methods,
          source: source,
          child_recordables: child_recordables.freeze
        }
      end

      existing_source = existing[:source]
      if existing_source.present? && source.present? && existing_source != source
        raise ArgumentError,
              "capability #{capability_name.inspect} is already registered by #{existing_source.inspect}"
      end

      merged_children = (Array(existing[:child_recordables]) + child_recordables).uniq.sort.freeze
      existing[:mod] = mod if mod
      existing[:recording_methods] = recording_methods if recording_methods
      existing[:source] = source if existing_source.blank? && source.present?
      existing[:child_recordables] = merged_children
      existing
    end

    def normalize_capability_name(name)
      value = name.to_s.strip
      raise ArgumentError, "capability is required" if value.blank?

      value.to_sym
    end

    def normalize_capability_recording_methods!(mod)
      return if mod.nil?

      raise ArgumentError, "recording_methods must be a module" unless mod.is_a?(Module)

      mod
    end

    def normalize_capability_source(source)
      source.to_s.strip.presence
    end

    def normalize_capability_child_recordables(child_recordables)
      Array(child_recordables).map do |child|
        type_name = RecordingStudio::Identity.type_name_for(child)
        if type_name.blank?
          raise RecordingStudio::InvalidRecordableDeclaration, "child_recordables cannot include blank values"
        end

        type_name
      end.uniq.sort.freeze
    end

    def find_idempotent_event(recording, idempotency_key)
      return unless recording&.persisted? && idempotency_key

      recording.events.find_by(idempotency_key: idempotency_key)
    end

    def reload_recording_for_hierarchy!(recording, name)
      unless recording.respond_to?(:id) && recording.id.present?
        raise ArgumentError, "#{name} must be a persisted recording"
      end

      RecordingStudio::Recording.unscoped.lock.find(recording.id)
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
