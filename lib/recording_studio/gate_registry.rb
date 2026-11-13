# frozen_string_literal: true

module RecordingStudio
  class GateRegistry
    Check = Data.define(:name, :callable, :priority, :sequence)

    class << self
      def add(gate, check, handler, priority)
        mutex.synchronize do
          checks = (registry[gate] ||= {})
          replaced = checks.key?(check)
          sequence = replaced ? checks[check].sequence : next_sequence
          checks[check] = Check.new(name: check, callable: handler, priority: priority, sequence: sequence)
          replaced
        end
      end

      def remove(gate, check)
        mutex.synchronize do
          checks = registry[gate]
          return false unless checks&.delete(check)

          registry.delete(gate) if checks.empty?
          true
        end
      end

      def registered?(gate)
        mutex.synchronize { registry.key?(gate) }
      end

      def snapshot(gate)
        mutex.synchronize { locked_snapshot(gate) }
      end

      def reset!
        mutex.synchronize do
          @registry = {}
          @sequence = 0
        end
      end

      private

      def locked_snapshot(gate)
        checks = registry[gate] || {}
        overrides = overrides_for(gate)
        unknown = overrides.keys - checks.keys
        items = checks.values.map { |check| entry(gate, check, overrides[check.name]) }
        [items.sort_by { |item| [item[:priority], item[:sequence]] }, unknown]
      end

      def entry(gate, check, override)
        settings = override || {}
        priority = settings.fetch(:priority, check.priority)
        enabled = settings.fetch(:enabled, true)
        listing = { name: check.name, priority: priority, enabled: enabled }.freeze
        {
          gate: gate, name: check.name, callable: check.callable, priority: priority,
          sequence: check.sequence, enabled: enabled, listing: listing
        }
      end

      def overrides_for(gate)
        RecordingStudio.configuration.gate_overrides[gate] || {}
      end

      def registry
        @registry ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def next_sequence
        @sequence = (@sequence || 0) + 1
      end
    end
  end
end
