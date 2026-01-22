# frozen_string_literal: true

require "set"

module RecordingStudio
  module HasRecordingsContainer
    extend ActiveSupport::Concern

    included do
      has_many :recordings, as: :container, class_name: "RecordingStudio::Recording", dependent: :destroy
    end

    def record(recordable_or_class, actor: nil, metadata: {}, parent_recording: nil, &block)
      recordable = build_recordable(recordable_or_class)
      yield(recordable) if block_given?
      recordable.save!

      RecordingStudio.record!(
        action: "created",
        recordable: recordable,
        container: self,
        parent_recording: parent_recording,
        actor: actor,
        metadata: metadata
      ).recording
    end

    def revise(recording, actor: nil, metadata: {}, &block)
      recordable = duplicate_recordable(recording.recordable)
      yield(recordable) if block_given?
      recordable.save!

      RecordingStudio.record!(
        action: "updated",
        recordable: recordable,
        recording: recording,
        container: self,
        actor: actor,
        metadata: metadata
      ).recording
    end

    def unrecord(recording, actor: nil, metadata: {}, cascade: false)
      cascade ||= RecordingStudio.configuration.unrecord_children
      unrecord_with_cascade(recording, actor: actor, metadata: metadata, cascade: cascade, seen: Set.new)
    end

    def restore(recording, actor: nil, metadata: {}, cascade: false)
      cascade ||= RecordingStudio.configuration.unrecord_children
      restore_with_cascade(recording, actor: actor, metadata: metadata, cascade: cascade, seen: Set.new)
    end

    def log_event(recording, action:, actor: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil)
      recording.log_event!(
        action: action,
        actor: actor,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    def revert(recording, to_recordable:, actor: nil, metadata: {})
      RecordingStudio.record!(
        action: "reverted",
        recordable: to_recordable,
        recording: recording,
        container: self,
        actor: actor,
        metadata: metadata
      ).recording
    end

    def recordings_of(recordable_class)
      recordings.of_type(recordable_class)
    end

    private

    def unrecord_with_cascade(recording, actor:, metadata:, cascade:, seen:)
      return recording if recording.nil?

      key = [recording.class.name, recording.id || recording.object_id]
      return recording if seen.include?(key)

      seen.add(key)

      if cascade
        children = Array(RecordingStudio.configuration.cascade_unrecord&.call(recording)).compact
        children.each do |child|
          unrecord_with_cascade(child, actor: actor, metadata: metadata, cascade: true, seen: seen)
        end
      end

      event = RecordingStudio.record!(
        action: "deleted",
        recordable: recording.recordable,
        recording: recording,
        container: self,
        actor: actor,
        metadata: metadata
      )

      if RecordingStudio.configuration.unrecord_mode == :hard
        recording.destroy!
      else
        recording.update!(trashed_at: Time.current)
      end

      event.recording
    end

    def restore_with_cascade(recording, actor:, metadata:, cascade:, seen:)
      return recording if recording.nil?

      key = [recording.class.name, recording.id || recording.object_id]
      return recording if seen.include?(key)

      seen.add(key)

      if cascade
        children = Array(RecordingStudio.configuration.cascade_unrecord&.call(recording)).compact
        children.each do |child|
          restore_with_cascade(child, actor: actor, metadata: metadata, cascade: true, seen: seen)
        end
      end

      if recording.trashed_at
        RecordingStudio.record!(
          action: "restored",
          recordable: recording.recordable,
          recording: recording,
          container: self,
          actor: actor,
          metadata: metadata
        )

        recording.update!(trashed_at: nil)
      end

      recording
    end

    def build_recordable(recordable_or_class)
      recordable_or_class.is_a?(Class) ? recordable_or_class.new : recordable_or_class
    end

    def duplicate_recordable(recordable)
      strategy = RecordingStudio.configuration.recordable_dup_strategy
      return strategy.call(recordable) if strategy.respond_to?(:call)

      duplicated = recordable.dup
      duplicated.recordings_count = 0 if duplicated.respond_to?(:recordings_count=)
      duplicated.events_count = 0 if duplicated.respond_to?(:events_count=)
      duplicated
    end
  end
end