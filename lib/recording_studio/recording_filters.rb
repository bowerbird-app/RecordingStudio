# frozen_string_literal: true

module RecordingStudio
  # Named filters for Recording.kept. Stored in lib so a code reload leaves them in place.
  module RecordingFilters
    IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]{0,62}\z/
    Filter = Data.define(:name, :relation, :sql)

    class << self
      def register(name, sql:, &block)
        filter_name = normalize_name(name)
        raise ArgumentError, "recording filter requires a block" unless block
        raise ArgumentError, "recording filter sql must respond to call" unless sql.respond_to?(:call)

        filter = Filter.new(name: filter_name, relation: block, sql: sql)
        mutex.synchronize { registry[filter_name] = filter }
        filter_name
      end

      def unregister(name)
        filter_name = normalize_name(name)
        mutex.synchronize { !registry.delete(filter_name).nil? }
      end

      def reset!
        mutex.synchronize { @registry = {} }
      end

      def apply(relation)
        snapshot.reduce(relation) { |current, filter| apply_filter(filter, current) }
      end

      def kept_sql(table = "recording_studio_recordings")
        identifier = normalize_table(table)
        filters = snapshot
        return "1=1" if filters.empty?

        quoted = quote_table(identifier)
        filters.map { |filter| sql_fragment(filter, quoted) }.join(" AND ")
      end

      private

      def apply_filter(filter, relation)
        filtered = filter.relation.call(relation)
        return filtered if filtered.is_a?(ActiveRecord::Relation)

        raise ArgumentError, "recording filter #{filter.name.inspect} must return a relation"
      end

      def sql_fragment(filter, quoted_table)
        fragment = filter.sql.call(quoted_table)
        return "(#{fragment})" if fragment.is_a?(String) && !fragment.strip.empty?

        raise ArgumentError, "recording filter #{filter.name.inspect} sql must return a SQL string"
      end

      def snapshot
        mutex.synchronize { registry.values }
      end

      def registry
        @registry ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def normalize_name(name)
        unless name.is_a?(String) || name.is_a?(Symbol)
          raise ArgumentError, "recording filter name must be a non-empty string or symbol"
        end

        filter_name = name.to_s.strip
        raise ArgumentError, "recording filter name must be a non-empty string or symbol" if filter_name.empty?

        filter_name.to_sym
      end

      def normalize_table(table)
        raise ArgumentError, "table must be a SQL identifier" unless table.is_a?(String) || table.is_a?(Symbol)

        identifier = table.to_s
        return identifier if IDENTIFIER.match?(identifier)

        raise ArgumentError, "table must be a SQL identifier"
      end

      def quote_table(identifier)
        RecordingStudio::Recording.connection.quote_table_name(identifier)
      end
    end
  end
end
