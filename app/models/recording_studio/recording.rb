# frozen_string_literal: true

module RecordingStudio
  # rubocop:disable Metrics/ClassLength
  class Recording < ApplicationRecord
    self.table_name = "recording_studio_recordings"

    include RecordingStudio::RecordingTrashable
    include RecordingStudio::RecordingTrashableScopes
    include RecordingStudio::RecordingTrashableCounters

    belongs_to :root_recording, class_name: "RecordingStudio::Recording", optional: true
    belongs_to :parent_recording, class_name: "RecordingStudio::Recording", optional: true,
                                  inverse_of: :child_recordings
    has_many :child_recordings, class_name: "RecordingStudio::Recording", foreign_key: :parent_recording_id,
                                inverse_of: :parent_recording, dependent: :nullify
    has_many :events, -> { recent }, class_name: "RecordingStudio::Event", inverse_of: :recording, dependent: :destroy

    validate :parent_recording_root_consistency
    validate :parent_recording_must_not_create_cycle

    before_create :assign_root_recording_id
    after_create :set_self_root_recording_id, if: -> { parent_recording_id.nil? && root_recording_id.nil? }

    default_scope { where(trashed_at: nil).order(updated_at: :desc) }
    scope :recent, -> { order(updated_at: :desc) }
    scope :for_root, ->(root_id) { where(root_recording_id: root_id) }
    scope :of_type, ->(klass) { where(recordable_type: klass.to_s) }

    def events(actions: nil, actor: nil, actor_type: nil, actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)
      scope = association(:events).scope
      scope = scope.with_action(actions) if actions.present?
      scope = scope.by_actor(actor) if actor.present?
      scope = scope.where(actor_type: actor_type) if actor_type.present?
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where(occurred_at: from..) if from.present?
      scope = scope.where(occurred_at: ..to) if to.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def record(recordable_or_class, actor: nil, impersonator: nil, metadata: {}, parent_recording: nil)
      recordable = build_recordable_instance(recordable_or_class)
      yield(recordable) if block_given?
      recordable.save!

      root = root_recording || self
      resolved_parent = parent_recording || root

      RecordingStudio.record!(
        action: "created",
        recordable: recordable,
        root_recording: root,
        parent_recording: resolved_parent,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def revise(recording, actor: nil, impersonator: nil, metadata: {})
      assert_recording_belongs_to_root!(recording)

      recordable = duplicate_recordable(recording.recordable)
      yield(recordable) if block_given?
      recordable.save!

      RecordingStudio.record!(
        action: "updated",
        recordable: recordable,
        recording: recording,
        root_recording: root_recording || self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def log_event(recording = self, action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current,
                  idempotency_key: nil)
      assert_recording_belongs_to_root!(recording)

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
      assert_recording_belongs_to_root!(recording)

      RecordingStudio.record!(
        action: "reverted",
        recordable: to_recordable,
        recording: recording,
        root_recording: root_recording || self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata
      ).recording
    end

    def recordings_query(include_children: false, type: nil, id: nil, parent_id: nil,
                         created_after: nil, created_before: nil, updated_after: nil, updated_before: nil,
                         order: nil, recordable_order: nil, recordable_filters: nil, recordable_scope: nil,
                         limit: nil, offset: nil)
      root_id = root_recording_id || self.id
      base_scope = RecordingStudio::Recording.for_root(root_id)
      scope = include_children ? base_scope : base_scope.where(parent_recording_id: root_id)
      scope = scope.of_type(type) if type.present?
      scope = scope.where(recordable_id: id) if id.present?
      scope = scope.where(parent_recording_id: parent_id) if parent_id.present?
      scope = scope.where(created_at: created_after..) if created_after.present?
      scope = scope.where(created_at: ..created_before) if created_before.present?
      scope = scope.where(updated_at: updated_after..) if updated_after.present?
      scope = scope.where(updated_at: ..updated_before) if updated_before.present?
      if type.present? &&
         (recordable_order.present? || recordable_filters.present? || recordable_scope.respond_to?(:call))
        recordable_class = type.is_a?(Class) ? type : type.to_s.safe_constantize
        if recordable_class
          recordable_table = recordable_class.connection.quote_table_name(recordable_class.table_name)
          scope = scope.where(recordable_type: recordable_class.name)
          scope = scope.joins(
            "INNER JOIN #{recordable_table} ON #{recordable_table}.id = recording_studio_recordings.recordable_id"
          )
          scope = apply_recordable_filters(scope, recordable_filters, recordable_class)
          if recordable_scope.respond_to?(:call)
            custom_scope = recordable_scope.call(scope)
            scope = custom_scope if custom_scope.is_a?(ActiveRecord::Relation)
          end
          safe_recordable_order = sanitize_order_for_model(recordable_order, recordable_class)
          scope = scope.reorder(safe_recordable_order) if safe_recordable_order.present?
        end
      end
      scope = enforce_recordings_scope(scope, root_id: root_id, include_children: include_children)
      safe_recording_order = sanitize_order_for_model(order, RecordingStudio::Recording)
      scope = scope.reorder(safe_recording_order) if safe_recording_order.present?
      scope = scope.limit(limit) if limit.present?
      scope = scope.offset(offset) if offset.present?
      scope
    end

    def recordings_of(recordable_class)
      recordings_query.of_type(recordable_class)
    end

    def name
      RecordingStudio::Labels.name_for(recordable)
    end

    alias label name

    def type_label
      RecordingStudio::Labels.type_label_for(recordable || recordable_type)
    end

    def title
      RecordingStudio::Labels.title_for(recordable)
    end

    def summary
      RecordingStudio::Labels.summary_for(recordable)
    end

    def log_event!(action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current,
                   idempotency_key: nil)
      RecordingStudio.record!(
        action: action,
        recordable: recordable,
        recording: self,
        root_recording: root_recording || self,
        actor: actor,
        impersonator: impersonator,
        metadata: metadata,
        occurred_at: occurred_at,
        idempotency_key: idempotency_key
      )
    end

    private

    def assign_root_recording_id
      return if parent_recording_id.nil?

      parent_root_id = parent_recording&.root_recording_id ||
                       self.class.unscoped.where(id: parent_recording_id).pick(:root_recording_id)
      self.root_recording_id = parent_root_id || parent_recording_id
    end

    def set_self_root_recording_id
      update!(root_recording_id: id)
    end

    def build_recordable_instance(recordable_or_class)
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

    def assert_recording_belongs_to_root!(recording)
      return if recording.nil?

      root_id = root_recording_id || id
      return if recording.root_recording_id == root_id

      raise ArgumentError, "recording must belong to this root recording"
    end

    def parent_recording_root_consistency
      return unless parent_recording

      my_root = root_recording_id || parent_recording&.root_recording_id
      return if my_root == parent_recording.root_recording_id

      errors.add(:parent_recording_id, "must belong to the same root recording")
    end

    def parent_recording_must_not_create_cycle
      return if parent_recording_id.nil?

      if id.present? && parent_recording_id == id
        errors.add(:parent_recording_id, "cannot be itself or a descendant recording")
        return
      end

      return if id.blank?

      visited_ids = Set.new
      current_parent_id = parent_recording_id

      while current_parent_id.present?
        return if visited_ids.include?(current_parent_id)

        if current_parent_id == id
          errors.add(:parent_recording_id, "cannot be itself or a descendant recording")
          return
        end

        visited_ids << current_parent_id
        current_parent_id = self.class.unscoped.where(id: current_parent_id).pick(:parent_recording_id)
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
