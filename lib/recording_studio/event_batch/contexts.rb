# frozen_string_literal: true

module RecordingStudio
  class EventBatch
    # Locks target recordings in id order and checks each row against its root.
    class Contexts
      def self.bind(prepared)
        new(prepared).bind
      end

      def initialize(prepared)
        @prepared = prepared
      end

      def bind
        locked = lock_recordings!
        roots = load_roots(locked)
        @prepared.map { |entry| bind_context(entry, locked, roots) }
      end

      private

      def lock_recordings!
        ids = @prepared.map { |entry| entry.fetch(:recording).id }
        locked = RecordingStudio::Recording.lock_ids!(ids).index_by { |recording| recording.id.to_s }
        missing = ids.map(&:to_s).uniq - locked.keys
        return locked if missing.empty?

        raise ArgumentError, "recording must be a persisted recording"
      end

      def load_roots(locked)
        ids = locked.values.map { |recording| root_id(recording) }.uniq
        found = locked.slice(*ids.map(&:to_s))
        missing = ids.map(&:to_s) - found.keys
        load_missing_roots(missing).each { |recording| found[recording.id.to_s] = recording }
        found
      end

      def root_id(recording)
        recording.root_recording_id.presence || recording.id
      end

      def load_missing_roots(ids)
        return [] if ids.empty?

        RecordingStudio::Recording.unscoped.where(id: ids).to_a
      end

      def bind_context(entry, locked, roots)
        recording = locked.fetch(entry.fetch(:recording).id.to_s)
        assert_same_recordable!(recording, entry.fetch(:recordable))
        entry.merge(recording: recording, root_recording: root_for!(recording, roots))
      end

      def assert_same_recordable!(recording, recordable)
        return if same_recordable?(recording, recordable)

        raise ArgumentError, "recordable must match the recording"
      end

      def same_recordable?(recording, recordable)
        return false unless comparable_recordable?(recordable)

        same_recordable_key?(recording, recordable)
      end

      def comparable_recordable?(recordable)
        recordable.respond_to?(:id) && recordable.id.present? && recordable.class.respond_to?(:polymorphic_name)
      end

      def same_recordable_key?(recording, recordable)
        recording.recordable_type == recordable.class.polymorphic_name &&
          recording.recordable_id.to_s == recordable.id.to_s
      end

      def root_for!(recording, roots)
        root = roots[root_id(recording).to_s]
        raise ArgumentError, "root_recording must be a root recording" if root.nil?

        RecordingStudio.assert_root_recording!(root)
        assert_recording_root!(root, recording)
        root
      end

      def assert_recording_root!(root, recording)
        RecordingStudio.assert_recording_belongs_to_root!(
          root,
          recording,
          message: "recording must belong to the provided root_recording"
        )
      end
    end
  end
end
