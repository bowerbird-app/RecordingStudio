# frozen_string_literal: true

module RecordingStudio
  class Recording < ApplicationRecord
    # Internal module for trash lifecycle operations: soft-delete, restore, hard-delete.
    # Extracted to support future modularization into an addon gem.
    module Trashable
      extend ActiveSupport::Concern

      # Soft-delete a recording and optionally cascade to children.
      # Respects RecordingStudio.configuration.include_children when include_children param is false.
      def trash(recording = self, actor: nil, impersonator: nil, metadata: {}, include_children: false)
        assert_recording_belongs_to_root!(recording)

        include_children ||= RecordingStudio.configuration.include_children
        delete_with_cascade(recording, actor: actor, impersonator: impersonator, metadata: metadata,
                                       cascade: include_children, seen: Set.new, mode: :soft)
      end

      # Permanently delete a recording and optionally cascade to children.
      # Respects RecordingStudio.configuration.include_children when include_children param is false.
      def hard_delete(recording = self, actor: nil, impersonator: nil, metadata: {}, include_children: false)
        assert_recording_belongs_to_root!(recording)

        include_children ||= RecordingStudio.configuration.include_children
        delete_with_cascade(recording, actor: actor, impersonator: impersonator, metadata: metadata,
                                       cascade: include_children, seen: Set.new, mode: :hard)
      end

      # Restore a soft-deleted recording and optionally cascade to children.
      # Respects RecordingStudio.configuration.include_children when include_children param is false.
      def restore(recording = self, actor: nil, impersonator: nil, metadata: {}, include_children: false)
        assert_recording_belongs_to_root!(recording)

        include_children ||= RecordingStudio.configuration.include_children
        restore_with_cascade(recording, actor: actor, impersonator: impersonator, metadata: metadata,
                                        cascade: include_children, seen: Set.new)
      end

      private

      # Recursively soft-delete or hard-delete a recording and optionally its children.
      # Creates a "trashed" or "deleted" event and updates trashed_at or destroys the record.
      def delete_with_cascade(recording, actor:, impersonator:, metadata:, cascade:, seen:, mode:)
        return recording if recording.nil?

        key = [recording.class.name, recording.id || recording.object_id]
        return recording if seen.include?(key)

        seen.add(key)

        if cascade
          children = recording.child_recordings.including_trashed
          children.each do |child|
            delete_with_cascade(
              child,
              actor: actor,
              impersonator: impersonator,
              metadata: metadata,
              cascade: true,
              seen: seen,
              mode: mode
            )
          end
        end

        action = mode == :hard ? "deleted" : "trashed"
        event = RecordingStudio.record!(
          action: action,
          recordable: recording.recordable,
          recording: recording,
          root_recording: root_recording || self,
          actor: actor,
          impersonator: impersonator,
          metadata: metadata
        )

        if mode == :hard
          recording.destroy!
        else
          recording.update!(trashed_at: Time.current)
        end

        event.recording
      end

      # Recursively restore a recording and optionally its children.
      # Creates a "restored" event and clears trashed_at.
      def restore_with_cascade(recording, actor:, impersonator:, metadata:, cascade:, seen:)
        return recording if recording.nil?

        key = [recording.class.name, recording.id || recording.object_id]
        return recording if seen.include?(key)

        seen.add(key)

        if cascade
          children = recording.child_recordings.including_trashed
          children.each do |child|
            restore_with_cascade(
              child,
              actor: actor,
              impersonator: impersonator,
              metadata: metadata,
              cascade: true,
              seen: seen
            )
          end
        end

        if recording.trashed_at
          RecordingStudio.record!(
            action: "restored",
            recordable: recording.recordable,
            recording: recording,
            root_recording: root_recording || self,
            actor: actor,
            impersonator: impersonator,
            metadata: metadata
          )

          recording.update!(trashed_at: nil)
        end

        recording
      end
    end
  end
end
