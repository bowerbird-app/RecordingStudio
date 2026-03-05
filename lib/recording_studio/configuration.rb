# frozen_string_literal: true

require_relative "hooks"

module RecordingStudio
  class Configuration
    class Features
      attr_reader :move, :copyable, :device_sessions

      def initialize
        @move = true
        @copyable = true
        @device_sessions = true
      end

      def move=(value)
        @move = boolean_from?(value)
      end

      def copyable=(value)
        @copyable = boolean_from?(value)
      end

      def device_sessions=(value)
        @device_sessions = boolean_from?(value)
      end

      def move?
        move
      end

      def copyable?
        copyable
      end

      def device_sessions?
        device_sessions
      end

      def merge!(hash)
        return unless hash.respond_to?(:each)

        hash.each do |k, v|
          setter = "#{k}="
          public_send(setter, v) if respond_to?(setter)
        end
      end

      def to_h
        {
          move: move,
          copyable: copyable,
          device_sessions: device_sessions
        }
      end

      private

      def boolean_from?(value)
        if defined?(ActiveModel::Type::Boolean)
          !!ActiveModel::Type::Boolean.new.cast(value)
        else
          !!value
        end
      end
    end

    attr_accessor :actor, :impersonator, :event_notifications_enabled,
                  :idempotency_mode, :recordable_dup_strategy,
                  :include_children
    attr_reader :recordable_types, :hooks, :features

    # rubocop:disable Metrics/MethodLength
    def initialize
      @recordable_types = []
      @capabilities = {}
      @capability_options = {}
      @actor = -> { defined?(Current) ? Current.actor : nil }
      @impersonator = -> { defined?(Current) ? Current.impersonator : nil }
      @event_notifications_enabled = true
      @idempotency_mode = :return_existing
      @recordable_dup_strategy = :dup
      @include_children = false
      @hooks = Hooks.new
      @features = Features.new
    end
    # rubocop:enable Metrics/MethodLength

    def instrumentation_enabled
      event_notifications_enabled
    end

    def instrumentation_enabled=(value)
      self.event_notifications_enabled = value
    end

    def recordable_types=(types)
      @recordable_types = Array(types).map { |type| type.is_a?(Class) ? type.name : type.to_s }.uniq
    end

    def enable_capability(capability, on:)
      type_name = on.is_a?(Class) ? on.name : on.to_s
      @capabilities[type_name] ||= Set.new
      @capabilities[type_name].add(capability.to_sym)
    end

    def capability_enabled?(capability, for_type:)
      type_name = for_type.is_a?(Class) ? for_type.name : for_type.to_s
      @capabilities[type_name]&.include?(capability.to_sym) || false
    end

    def set_capability_options(capability, on:, **options)
      type_name = on.is_a?(Class) ? on.name : on.to_s
      @capability_options[[capability.to_sym, type_name]] = options
    end

    def capability_options(capability, for_type:)
      type_name = for_type.is_a?(Class) ? for_type.name : for_type.to_s
      @capability_options[[capability.to_sym, type_name]]
    end

    def to_h
      {
        recordable_types: recordable_types,
        event_notifications_enabled: event_notifications_enabled,
        idempotency_mode: idempotency_mode,
        include_children: include_children,
        recordable_dup_strategy: recordable_dup_strategy,
        features: features.to_h,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        if key == "features"
          features.merge!(v)
          next
        end

        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end
  end
end
