# frozen_string_literal: true

require_relative "hooks"

module RecordingStudio
  class Configuration
    REMOVED_CONFIGURATION_KEYS = %w[features].freeze

    attr_accessor(
      :actor,
      :impersonator,
      :event_notifications_enabled,
      :idempotency_mode,
      :recordable_dup_strategy
    )
    attr_reader :recordable_types, :hooks, :recordable_dup_strategies

    def initialize
      @recordable_types = []
      @capabilities = {}
      @capability_options = {}
      @actor = -> { defined?(Current) ? Current.actor : nil }
      @impersonator = -> { defined?(Current) ? Current.impersonator : nil }
      @event_notifications_enabled = true
      @idempotency_mode = :return_existing
      @recordable_dup_strategy = :dup
      @recordable_dup_strategies = {}
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
        recordable_dup_strategy: recordable_dup_strategy,
        recordable_dup_strategies: recordable_dup_strategies.keys.sort,
        hooks_registered: hooks.registered_counts
      }
    end

    def register_recordable_dup_strategy(type, callable = nil, &block)
      strategy = callable || block
      raise ArgumentError, "duplication strategy must respond to call" unless strategy.respond_to?(:call)

      type_name = RecordingStudio::Identity.type_name_for(type)
      raise ArgumentError, "recordable type is required" if type_name.blank?

      @recordable_dup_strategies[type_name] = strategy
    end

    def recordable_dup_strategy_for(recordable_or_type)
      type_name = RecordingStudio::Identity.type_name_for(recordable_or_type)
      return recordable_dup_strategy if type_name.blank?

      @recordable_dup_strategies[type_name] || recordable_dup_strategy
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        if REMOVED_CONFIGURATION_KEYS.include?(key)
          warn_removed_configuration_key!(key)
          next
        end

        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end

    private

    def warn_removed_configuration_key!(key)
      message = "[RecordingStudio] '#{key}' configuration has been removed from core. " \
                "Move access/device-session configuration to the extracted addon gem."

      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
    end
  end
end
