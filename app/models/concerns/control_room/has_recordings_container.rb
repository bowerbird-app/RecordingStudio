# frozen_string_literal: true

module ControlRoom
  module HasRecordingsContainer
    extend ActiveSupport::Concern

    included do
      has_many :recordings, as: :container, class_name: "ControlRoom::Recording", dependent: :destroy
    end

    def record(recordable_or_class, actor: nil, metadata: {}, &block)
      recordable = build_recordable(recordable_or_class)
      yield(recordable) if block_given?
      recordable.save!

      ControlRoom.record!(
        action: "created",
        recordable: recordable,
        container: self,
        actor: actor,
        metadata: metadata
      ).recording
    end

    def revise(recording, actor: nil, metadata: {}, &block)
      recordable = duplicate_recordable(recording.recordable)
      yield(recordable) if block_given?
      recordable.save!

      ControlRoom.record!(
        action: "updated",
        recordable: recordable,
        recording: recording,
        container: self,
        actor: actor,
        metadata: metadata
      ).recording
    end

    def unrecord(recording, actor: nil, metadata: {})
      event = ControlRoom.record!(
        action: "deleted",
        recordable: recording.recordable,
        recording: recording,
        container: self,
        actor: actor,
        metadata: metadata
      )

      if ControlRoom.configuration.unrecord_mode == :hard
        recording.destroy!
      else
        recording.update!(discarded_at: Time.current)
      end

      event.recording
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
      ControlRoom.record!(
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

    def build_recordable(recordable_or_class)
      recordable_or_class.is_a?(Class) ? recordable_or_class.new : recordable_or_class
    end

    def duplicate_recordable(recordable)
      strategy = ControlRoom.configuration.recordable_dup_strategy
      return strategy.call(recordable) if strategy.respond_to?(:call)

      recordable.dup
    end
  end
end
