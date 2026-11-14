# frozen_string_literal: true

module RecordingStudio
  # Row locks for writes. Roots are locked before any other recording, and each
  # phase locks ids in ascending order so two moves cannot deadlock.
  module Locks
    SHARE_LOCK = "FOR SHARE"

    module_function

    def lock_for_move!(recording, to_parent:, to_root:)
      Move.new(recording, to_parent, to_root).call
    end

    def lock_recording!(recording, name, mode:)
      unless recording.respond_to?(:id) && recording.id.present?
        raise ArgumentError, "#{name} must be a persisted recording"
      end

      scope = RecordingStudio::Recording.unscoped
      scope = scope.lock(mode) if mode.present?
      scope.find(recording.id)
    end

    class Move
      RETRY = "The tree changed while locking. Retry the move."
      NODE_LOCK_PASSES = 5

      def initialize(recording, to_parent, to_root)
        @recording = recording
        @to_parent = to_parent
        @to_root = to_root
      end

      def call
        assert_transaction_open!
        load_targets!
        assert_same_root!
        lock_rows!([@source_root_id, @to_root.id])
        pack(lock_nodes!)
      end

      private

      def assert_transaction_open!
        return if RecordingStudio::Recording.connection.transaction_open?

        raise ArgumentError, "lock_for_move! must run inside a transaction"
      end

      def load_targets!
        @recording = persisted!(@recording, "recording")
        @to_parent = persisted!(@to_parent, "to_parent")
        @to_root = persisted!(@to_root, "to_root")
        @source_root_id = root_id_for(@recording)
      end

      def persisted!(recording, name)
        unless recording.respond_to?(:id) && recording.id.present?
          raise ArgumentError, "#{name} must be a persisted recording"
        end

        find(recording.id)
      end

      def assert_same_root!
        return if root_id_for(@to_parent) == @to_root.id

        raise ArgumentError, "to_parent must belong to to_root"
      end

      def lock_nodes!
        locked = []
        descendants = []

        NODE_LOCK_PASSES.times do
          descendants = find(@recording.id).descendant_ids
          pending = pending_node_ids(descendants, locked)
          return descendants if pending.empty?

          assert_lock_order!(pending, locked)
          locked.concat(lock_pending!(pending))
        end

        raise MoveConflict, RETRY
      end

      def pending_node_ids(descendants, locked)
        ids = [@recording.id, @to_parent.id, *descendants].map(&:to_s)
        ids.uniq - [@source_root_id, @to_root.id].map(&:to_s) - locked
      end

      def assert_lock_order!(pending, locked)
        return if locked.empty?
        return if pending.all? { |id| id > locked.max }

        raise MoveConflict, RETRY
      end

      def lock_pending!(ids)
        found = lock_rows(ids).map { |row| row.id.to_s }
        required = [@recording.id.to_s, @to_parent.id.to_s] & ids
        return found if (required - found).empty?

        raise ArgumentError, "recording must be a persisted recording"
      end

      def pack(descendant_ids)
        reloaded = reload_targets
        assert_stable!(reloaded)
        reloaded.merge(descendant_ids: descendant_ids).freeze
      end

      def reload_targets
        {
          recording: find(@recording.id),
          to_parent: find(@to_parent.id),
          to_root: find(@to_root.id),
          source_root: find(@source_root_id)
        }
      end

      def assert_stable!(reloaded)
        raise MoveConflict, RETRY if root_id_for(reloaded[:recording]) != @source_root_id
        raise MoveConflict, RETRY if root_id_for(reloaded[:to_parent]) != @to_root.id

        RecordingStudio.assert_root_recording!(reloaded[:to_root])
        RecordingStudio.assert_root_recording!(reloaded[:source_root])
      end

      def lock_rows!(ids)
        rows = lock_rows(ids)
        found = rows.map { |row| row.id.to_s }.sort
        return rows if found == Array(ids).map(&:to_s).uniq.sort

        raise ArgumentError, "recording must be a persisted recording"
      end

      def lock_rows(ids)
        normalized = Array(ids).map(&:to_s).uniq.sort
        return [] if normalized.empty?

        RecordingStudio::Recording.lock_ids!(normalized).to_a
      end

      def find(id)
        RecordingStudio::Recording.unscoped.find(id)
      end

      def root_id_for(recording)
        RecordingStudio.root_recording_id_for(recording)
      end
    end
  end
end
