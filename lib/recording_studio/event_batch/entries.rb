# frozen_string_literal: true

module RecordingStudio
  class EventBatch
    # Normalizes batch entries the same way record! normalizes one write.
    class Entries
      def self.prepare(entries)
        new(entries).prepare
      end

      def initialize(entries)
        @entries = entries
      end

      def prepare
        assert_entries!
        base = Time.current
        @entries.map.with_index { |entry, index| prepare_entry(entry, index, base) }
      end

      private

      def assert_entries!
        return if @entries.is_a?(Array)

        raise ArgumentError, "entries must be an Array"
      end

      def prepare_entry(entry, index, base)
        fields = symbolized_entry(entry)
        identity_for(fields).merge(write_for(fields, index, base))
      end

      def symbolized_entry(entry)
        raise ArgumentError, "entry must be a Hash" unless entry.is_a?(Hash)

        fields = entry.symbolize_keys
        reject_idempotency!(fields)
        fields
      end

      def reject_idempotency!(fields)
        return unless fields.key?(:idempotency_key)

        raise ArgumentError, "record_events! does not accept idempotency_key"
      end

      def identity_for(fields)
        {
          action: fields[:action],
          recording: persisted_recording!(fields[:recording]),
          recordable: fields[:recordable]
        }
      end

      def write_for(fields, index, base)
        {
          actor: resolve_actor(fields[:actor]),
          impersonator: resolve_impersonator(fields[:impersonator]),
          metadata: RecordingStudio::Metadata.normalize(fields.fetch(:metadata, {})),
          occurred_at: occurred_at_for(fields[:occurred_at], index, base)
        }
      end

      def persisted_recording!(recording)
        return recording if recording.is_a?(RecordingStudio::Recording) && recording.persisted?

        raise ArgumentError, "recording must be a persisted recording"
      end

      def resolve_actor(actor)
        chosen = actor || RecordingStudio.configuration.actor&.call
        RecordingStudio::Authorization.assert_actor!(chosen)
      end

      def resolve_impersonator(impersonator)
        impersonator || RecordingStudio.configuration.impersonator&.call
      end

      def occurred_at_for(occurred_at, index, base)
        return occurred_at unless occurred_at.nil?

        base + Rational(index, 1_000_000)
      end
    end
  end
end
