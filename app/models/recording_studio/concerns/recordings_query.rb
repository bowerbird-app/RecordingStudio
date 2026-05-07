# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module RecordingStudio
  module Concerns
    module RecordingsQuery
      extend ActiveSupport::Concern

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
      def recordings_query(include_children: false, type: nil, id: nil, parent_id: nil,
                           created_after: nil, created_before: nil, updated_after: nil, updated_before: nil,
                           order: nil, recordable_order: nil, recordable_filters: nil, recordable_scope: nil,
                           limit: nil, offset: nil)
        root_id = RecordingStudio.root_recording_id_for(root_recording_or_self)
        base_scope = RecordingStudio::Recording.for_root(root_id)
        scope = include_children ? base_scope : base_scope.where(parent_recording_id: root_id)
        scope = scope.of_type(type) if type.present?
        scope = scope.where(recordable_id: id) if id.present?
        scope = scope.where(parent_recording_id: parent_id) if parent_id.present?
        scope = scope.where(created_at: created_after..) if created_after.present?
        scope = scope.where(created_at: ..created_before) if created_before.present?
        scope = scope.where(updated_at: updated_after..) if updated_after.present?
        scope = scope.where(updated_at: ..updated_before) if updated_before.present?
        scope = apply_recordable_query_options(
          scope,
          type: type,
          recordable_order: recordable_order,
          recordable_filters: recordable_filters,
          recordable_scope: recordable_scope
        )
        scope = enforce_recordings_scope(scope, root_id: root_id, include_children: include_children)
        scope = extend_recordings_query(scope)
        safe_recording_order = sanitize_order_for_model(order, RecordingStudio::Recording)
        scope = scope.reorder(safe_recording_order) if safe_recording_order.present?
        scope = scope.limit(limit) if limit.present?
        scope = scope.offset(offset) if offset.present?
        scope
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity

      private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def apply_recordable_query_options(scope, type:, recordable_order:, recordable_filters:, recordable_scope:)
        return scope unless type.present?

        query_options_present = recordable_order.present? ||
                                recordable_filters.present? ||
                                recordable_scope.respond_to?(:call)
        return scope unless query_options_present

        recordable_class = RecordingStudio.resolve_recordable_type(type)
        return scope.none unless recordable_class

        recordable_table = recordable_class.connection.quote_table_name(recordable_class.table_name)
        scoped = scope.where(recordable_type: recordable_class.name)
        scoped = scoped.joins(
          "INNER JOIN #{recordable_table} ON #{recordable_table}.id = recording_studio_recordings.recordable_id"
        )
        scoped = apply_recordable_filters(scoped, recordable_filters, recordable_class)
        scoped = apply_recordable_scope(scoped, recordable_scope)

        safe_recordable_order = sanitize_order_for_model(recordable_order, recordable_class)
        safe_recordable_order.present? ? scoped.reorder(safe_recordable_order) : scoped
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def apply_recordable_scope(scope, recordable_scope)
        return scope unless recordable_scope.respond_to?(:call)

        custom_scope = recordable_scope.call(scope)
        custom_scope.is_a?(ActiveRecord::Relation) ? custom_scope : scope
      end

      def extend_recordings_query(scope)
        if respond_to?(:apply_recordings_query_extensions, true)
          apply_recordings_query_extensions(scope)
        else
          scope
        end
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

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def sanitize_order_string(order_string, model_class)
        allowed_columns = model_class.column_names
        table_name = model_class.table_name
        quoted_table = model_class.connection.quote_table_name(table_name)

        fragments = order_string.split(",").filter_map do |segment|
          cleaned = segment.strip
          next if cleaned.blank?

          match = cleaned.match(
            /\A(?:(?<table>[a-zA-Z0-9_"`]+)\.)?(?<column>[a-zA-Z0-9_"`]+)(?:\s+(?<dir>asc|desc))?\z/i
          )
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
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
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
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    end
  end
end
# rubocop:enable Metrics/ModuleLength
