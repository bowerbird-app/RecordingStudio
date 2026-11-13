# frozen_string_literal: true

require_relative "gate_decision"
require_relative "gate_overrides"
require_relative "gate_registry"
require_relative "gate_run"

module RecordingStudio
  module Gates
    DEFAULT_PRIORITY = 100
    CONVENTIONAL_NAME = /\A[a-z0-9_]+(\.[a-z0-9_]+)+\z/

    class << self
      def register(gate_name, check_name, callable = nil, priority: DEFAULT_PRIORITY, &block)
        gate = normalize_gate_name(gate_name)
        check = normalize_name(check_name, "check name")
        handler = callable || block
        raise ArgumentError, "gate check must respond to call" unless handler.respond_to?(:call)

        replaced = GateRegistry.add(gate, check, handler, Integer(priority))
        warn_replaced(gate, check) if replaced
        check
      end

      def unregister(gate_name, check_name)
        GateRegistry.remove(normalize_gate_name(gate_name), normalize_name(check_name, "check name"))
      end

      def registered?(gate_name)
        GateRegistry.registered?(normalize_gate_name(gate_name))
      end

      def checks_for(gate_name)
        GateRun.listings(normalize_gate_name(gate_name))
      end

      def check(gate_name, actor:, recording: nil, **context)
        GateRun.call(
          normalize_gate_name(gate_name),
          actor: actor,
          recording: recording,
          **context
        )
      end

      def reset!
        GateRegistry.reset!
        RecordingStudio.configuration.gate_overrides = {}
      end

      def normalize_gate_name(value)
        name = normalize_name(value, "gate name")
        warn_unconventional_name(name)
        name
      end

      def normalize_name(value, label)
        unless value.is_a?(String) || value.is_a?(Symbol)
          raise ArgumentError, "#{label} must be a non-empty string or symbol"
        end

        name = value.to_s.strip
        raise ArgumentError, "#{label} must be a non-empty string or symbol" if name.empty?

        -name
      end

      private

      def warn_replaced(gate, check)
        RecordingStudio::Warnings.warn(
          "[RecordingStudio::Gates] Replacing check #{check.inspect} on gate #{gate.inspect}"
        )
      end

      def warn_unconventional_name(name)
        return if CONVENTIONAL_NAME.match?(name)
        return unless GateRegistry.claim_unconventional_warning(name)

        RecordingStudio::Warnings.warn(
          "[RecordingStudio::Gates] Gate name #{name.inspect} does not match <gem>.<gate>"
        )
      end
    end
  end
end
