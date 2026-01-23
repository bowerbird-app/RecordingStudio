# frozen_string_literal: true

require "set"

module RecordingStudio
  module HasRecordingsContainer
    extend ActiveSupport::Concern

    included do
      has_many :recordings, -> { where(parent_recording_id: nil) }, as: :container,
              class_name: "RecordingStudio::Recording", dependent: :destroy
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

    def trash(recording, actor: nil, metadata: {}, include_children: false)
      include_children ||= RecordingStudio.configuration.include_children
      delete_with_cascade(recording, actor: actor, metadata: metadata, cascade: include_children, seen: Set.new, mode: :soft)
    end

    def hard_delete(recording, actor: nil, metadata: {}, include_children: false)
      include_children ||= RecordingStudio.configuration.include_children
      delete_with_cascade(recording, actor: actor, metadata: metadata, cascade: include_children, seen: Set.new, mode: :hard)
    end

    def restore(recording, actor: nil, metadata: {}, include_children: false)
      include_children ||= RecordingStudio.configuration.include_children
      restore_with_cascade(recording, actor: actor, metadata: metadata, cascade: include_children, seen: Set.new)
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

    def recordings(include_children: false, type: nil, id: nil, parent_id: nil,
                   created_after: nil, created_before: nil, updated_after: nil, updated_before: nil,
                   order: nil, recordable_order: nil, recordable_filters: nil, recordable_scope: nil,
                   limit: nil, offset: nil)
      scope = include_children ? RecordingStudio::Recording.for_container(self) : association(:recordings).scope
      scope = scope.of_type(type) if type.present?
      scope = scope.where(recordable_id: id) if id.present?
      scope = scope.where(parent_recording_id: parent_id) if parent_id.present?
      scope = scope.where("created_at >= ?", created_after) if created_after.present?
      scope = scope.where("created_at <= ?", created_before) if created_before.present?
      scope = scope.where("updated_at >= ?", updated_after) if updated_after.present?
      scope = scope.where("updated_at <= ?", updated_before) if updated_before.present?
      if type.present? && (recordable_order.present? || recordable_filters.present? || recordable_scope.respond_to?(:call))
        recordable_class = type.is_a?(Class) ? type : type.to_s.safe_constantize
        if recordable_class
          recordable_table = recordable_class.connection.quote_table_name(recordable_class.table_name)
          scope = scope.where(recordable_type: recordable_class.name)
          scope = scope.joins("INNER JOIN #{recordable_table} ON #{recordable_table}.id = recording_studio_recordings.recordable_id")
          scope = scope.where(recordable_filters) if recordable_filters.present?
          scope = recordable_scope.call(scope) if recordable_scope.respond_to?(:call)
          scope = scope.reorder(recordable_order) if recordable_order.present?
        end
      end
      scope = scope.reorder(order) if order.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def recordings_of(recordable_class)
      recordings.of_type(recordable_class)
    end

    private

    def delete_with_cascade(recording, actor:, metadata:, cascade:, seen:, mode:)
      return recording if recording.nil?

      key = [recording.class.name, recording.id || recording.object_id]
      return recording if seen.include?(key)

      seen.add(key)

      if cascade
        children = recording.child_recordings.including_trashed
        children.each do |child|
          delete_with_cascade(child, actor: actor, metadata: metadata, cascade: true, seen: seen, mode: mode)
        end
      end

      action = mode == :hard ? "deleted" : "trashed"
      event = RecordingStudio.record!(
        action: action,
        recordable: recording.recordable,
        recording: recording,
        container: self,
        actor: actor,
        metadata: metadata
      )

      if mode == :hard
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
        children = recording.child_recordings.including_trashed
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
