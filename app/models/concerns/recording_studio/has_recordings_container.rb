# frozen_string_literal: true

require "set"

module RecordingStudio
  module HasRecordingsContainer
    extend ActiveSupport::Concern

    included do
      has_many :recordings, -> { where(parent_recording_id: nil) }, as: :container,
              class_name: "RecordingStudio::Recording", dependent: :destroy
    end

    def record(recordable_or_class, actor: nil, impersonator: nil, metadata: {}, parent_recording: nil, &block)
      recordable = build_recordable(recordable_or_class)
      yield(recordable) if block_given?
      recordable.save!

      RecordingStudio.record!(
        action: "created",
        recordable: recordable,
        container: self,
        parent_recording: parent_recording,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def revise(recording, actor: nil, impersonator: nil, metadata: {}, &block)
      recordable = duplicate_recordable(recording.recordable)
      yield(recordable) if block_given?
      recordable.save!

      RecordingStudio.record!(
        action: "updated",
        recordable: recordable,
        recording: recording,
        container: self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def trash(recording, actor: nil, impersonator: nil, metadata: {}, include_children: false)
      include_children ||= RecordingStudio.configuration.include_children
      delete_with_cascade(recording, actor: actor, impersonator: impersonator, metadata: metadata, cascade: include_children, seen: Set.new, mode: :soft)
    end

    def hard_delete(recording, actor: nil, impersonator: nil, metadata: {}, include_children: false)
      include_children ||= RecordingStudio.configuration.include_children
      delete_with_cascade(recording, actor: actor, impersonator: impersonator, metadata: metadata, cascade: include_children, seen: Set.new, mode: :hard)
    end

    def restore(recording, actor: nil, impersonator: nil, metadata: {}, include_children: false)
      include_children ||= RecordingStudio.configuration.include_children
      restore_with_cascade(recording, actor: actor, impersonator: impersonator, metadata: metadata, cascade: include_children, seen: Set.new)
    end

    def log_event(recording, action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil)
      recording.log_event!(
        action: action,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    def revert(recording, to_recordable:, actor: nil, impersonator: nil, metadata: {})
      RecordingStudio.record!(
        action: "reverted",
        recordable: to_recordable,
        recording: recording,
        container: self,
        actor: actor,
        impersonator: impersonator,
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
          scope = apply_recordable_filters(scope, recordable_filters, recordable_class)
          scope = recordable_scope.call(scope) if recordable_scope.respond_to?(:call)
          safe_recordable_order = sanitize_order_for_model(recordable_order, recordable_class)
          scope = scope.reorder(safe_recordable_order) if safe_recordable_order.present?
        end
      end
      safe_recording_order = sanitize_order_for_model(order, RecordingStudio::Recording)
      scope = scope.reorder(safe_recording_order) if safe_recording_order.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def recordings_of(recordable_class)
      recordings.of_type(recordable_class)
    end

    private

    def delete_with_cascade(recording, actor:, impersonator:, metadata:, cascade:, seen:, mode:)
      return recording if recording.nil?

      key = [recording.class.name, recording.id || recording.object_id]
      return recording if seen.include?(key)

      seen.add(key)

      if cascade
        children = recording.child_recordings.including_trashed
        children.each do |child|
          delete_with_cascade(child, actor: actor, impersonator: impersonator, metadata: metadata, cascade: true, seen: seen, mode: mode)
        end
      end

      action = mode == :hard ? "deleted" : "trashed"
      event = RecordingStudio.record!(
        action: action,
        recordable: recording.recordable,
        recording: recording,
        container: self,
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

    def restore_with_cascade(recording, actor:, impersonator:, metadata:, cascade:, seen:)
      return recording if recording.nil?

      key = [recording.class.name, recording.id || recording.object_id]
      return recording if seen.include?(key)

      seen.add(key)

      if cascade
        children = recording.child_recordings.including_trashed
        children.each do |child|
          restore_with_cascade(child, actor: actor, impersonator: impersonator, metadata: metadata, cascade: true, seen: seen)
        end
      end

      if recording.trashed_at
        RecordingStudio.record!(
          action: "restored",
          recordable: recording.recordable,
          recording: recording,
          container: self,
          actor: actor,
          impersonator: impersonator,
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

    def sanitize_order_for_model(order, model_class)
      return if order.blank? || model_class.nil?

      case order
      when Hash
        sanitize_order_hash(order, model_class)
      when String, Symbol
        sanitize_order_string(order.to_s, model_class)
      else
        nil
      end
    end

    def sanitize_order_hash(order_hash, model_class)
      allowed_columns = model_class.column_names
      sanitized = order_hash.each_with_object({}) do |(column, direction), acc|
        column_name = column.to_s
        next unless allowed_columns.include?(column_name)

        dir = direction.to_s.downcase == "desc" ? :desc : :asc
        acc[column_name] = dir
      end

      sanitized.presence
    end

    def sanitize_order_string(order_string, model_class)
      allowed_columns = model_class.column_names
      table_name = model_class.table_name
      quoted_table = model_class.connection.quote_table_name(table_name)

      fragments = order_string.split(",").filter_map do |segment|
        cleaned = segment.strip
        next if cleaned.blank?

        match = cleaned.match(/\A(?:(?<table>[a-zA-Z0-9_"`]+)\.)?(?<column>[a-zA-Z0-9_"`]+)(?:\s+(?<dir>asc|desc))?\z/i)
        next unless match

        table = match[:table]&.gsub(/["`]/, "")
        column = match[:column]&.gsub(/["`]/, "")
        next unless allowed_columns.include?(column)
        next if table.present? && table != table_name

        direction = match[:dir].to_s.downcase == "desc" ? "DESC" : "ASC"
        quoted_column = model_class.connection.quote_column_name(column)
        "#{quoted_table}.#{quoted_column} #{direction}"
      end

      fragments.presence&.map { |fragment| Arel.sql(fragment) }
    end

    def apply_recordable_filters(scope, recordable_filters, recordable_class = nil)
      return scope if recordable_filters.blank?

      if recordable_filters.is_a?(Hash)
        return scope.where(recordable_filters) unless recordable_class

        allowed_columns = recordable_class.column_names.to_set
        sanitized = recordable_filters.each_with_object({}) do |(column, value), acc|
          column_name = column.to_s
          next unless allowed_columns.include?(column_name)

          acc[column_name] = value
        end

        sanitized.present? ? scope.where(recordable_class.table_name => sanitized) : scope
      elsif recordable_filters.is_a?(ActiveRecord::Relation)
        scope.merge(recordable_filters)
      elsif defined?(Arel::Nodes::Node) && recordable_filters.is_a?(Arel::Nodes::Node)
        scope.where(recordable_filters)
      else
        scope
      end
    end
  end
end
