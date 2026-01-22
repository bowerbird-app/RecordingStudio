# frozen_string_literal: true

require_relative "hooks"

module RecordingStudio
    class Configuration
      attr_accessor :recordable_types, :actor_provider, :event_notifications_enabled,
            :idempotency_mode, :unrecord_mode, :recordable_dup_strategy,
            :cascade_unrecord, :unrecord_children
    attr_reader :hooks

    def initialize
      @recordable_types = []
      @actor_provider = -> { defined?(Current) ? Current.actor : nil }
      @event_notifications_enabled = true
      @idempotency_mode = :return_existing
      @unrecord_mode = :soft
        @recordable_dup_strategy = :dup
        @cascade_unrecord = ->(recording) { recording.child_recordings.including_trashed }
        @unrecord_children = false
      @hooks = Hooks.new
    end

    def instrumentation_enabled
      event_notifications_enabled
    end

    def instrumentation_enabled=(value)
      self.event_notifications_enabled = value
    end

    def recordable_types=(types)
      @recordable_types = Array(types).map { |type| type.is_a?(Class) ? type.name : type.to_s }.uniq
    end

    def to_h
      {
        recordable_types: recordable_types,
        event_notifications_enabled: event_notifications_enabled,
        idempotency_mode: idempotency_mode,
        unrecord_mode: unrecord_mode,
          unrecord_children: unrecord_children,
        recordable_dup_strategy: recordable_dup_strategy,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end
  end
end
