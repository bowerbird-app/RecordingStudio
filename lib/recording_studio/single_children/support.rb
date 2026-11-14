# frozen_string_literal: true

module RecordingStudio
  module SingleChildren
    # Index SQL and the private lookups the registry methods share.
    module Support
      def index_types
        RecordingStudio::RecordableDeclarations.ensure_loaded!
        mutex.synchronize do
          grouped_parents.filter_map do |child_type, parent_sets|
            next unless parent_sets.include?(:any)
            next unless RecordingStudio::RecordableDeclarations.configured_recordable_type?(child_type)

            child_type
          end.sort
        end
      end

      def index_where_sql
        types = index_types
        return if types.empty?

        quoted = types.map { |type| quote_type(type) }
        "recordable_type IN (#{quoted.join(', ')})"
      end

      def pairwise_lines
        mutex.synchronize do
          grouped_parents.filter_map do |child_type, parent_sets|
            names = parent_sets.grep(Array).flatten.uniq.sort
            next if names.empty? || parent_sets.include?(:any)

            "#{child_type} under #{names.join(', ')}"
          end.sort
        end
      end

      private

      def occupied?(parent_recording, child_type, except:)
        scope = RecordingStudio::Recording.unscoped.where(
          parent_recording_id: parent_recording.id,
          recordable_type: child_type
        )
        scope = scope.where.not(id: except) if except
        scope.exists?
      end

      def rule_applies?(child_type, parent_type)
        grouped_parents.fetch(child_type, []).any? do |parents|
          parents == :any || parents.include?(parent_type)
        end
      end

      def grouped_parents
        registry.each_value.with_object({}) do |rule, grouped|
          grouped[rule.child_type] ||= []
          grouped[rule.child_type] << rule.parents
        end
      end

      def parents_for_declaration(declaration)
        case declaration.one_per_parent
        when true then :any
        when Array then declaration.one_per_parent.freeze
        end
      end

      def declaration_key(type_name)
        "#{DECLARATION_KEY_PREFIX}#{type_name}"
      end

      def parent_type_name(under)
        if under.respond_to?(:recordable_type) && under.recordable_type.present?
          return RecordingStudio::Identity.type_name_for(under.recordable_type)
        end

        RecordingStudio::Identity.type_name_for(under)
      end

      def normalize_parents(under)
        return :any if under == true
        return normalize_type_list(under) if under.is_a?(Array) || under.is_a?(String) || under.is_a?(Class)

        raise ArgumentError, "under must be true or a parent type"
      end

      def normalize_type_list(under)
        names = Array(under).map { |type| normalize_type_name(type, "parent type") }
        raise ArgumentError, "under must be true or a parent type" if names.empty?

        names.uniq.sort.freeze
      end

      def normalize_type_name(type, label)
        type_name = RecordingStudio::Identity.type_name_for(type)
        return type_name if type_name.present? && TYPE_NAME.match?(type_name)

        raise ArgumentError, "#{label} must be a recordable class name"
      end

      def normalize_key(key)
        raise ArgumentError, "key must be a non-empty string or symbol" unless key.is_a?(String) || key.is_a?(Symbol)

        rule_key = key.to_s.strip
        raise ArgumentError, "key must be a non-empty string or symbol" if rule_key.empty?

        rule_key
      end

      def quote_type(type_name)
        normalize_type_name(type_name, "child type")
        ActiveRecord::Base.connection.quote(type_name)
      end

      def registry
        @registry ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
