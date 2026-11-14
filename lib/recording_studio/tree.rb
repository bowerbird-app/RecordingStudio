# frozen_string_literal: true

# The walk SQL is one statement per query. Line length here is the statement, not branching.
# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
module RecordingStudio
  # SQL tree helpers for recording hierarchy traversal.
  # Uses recursive CTEs against PostgreSQL.
  module Tree
    MAX_WALK_DEPTH = 1000
    WALK_ERROR_PATTERN = /
      Recording\ tree\ contains\ a\ cycle\ at\ recording\ [0-9a-fA-F-]+
      |
      Recording\ tree\ walk\ exceeded\ the\ depth\ cap\ of\ \d+\ at\ recording\ [0-9a-fA-F-]+
    /x
    TABLE = "recording_studio_recordings"

    # Translates the walk's database error into TreeWalkError after rolling
    # back the failed statement, so an outer transaction can continue.
    # A depth-ordered page with a limit is read level by level. A recursive
    # CTE is materialized before an outer LIMIT, so it cannot stop early.
    module WalkGuard
      attr_accessor :subtree_seed

      def load(&)
        if subtree_page?
          load_subtree_page unless loaded?
          return self
        end

        guarded { super }
      end

      def pluck(*column_names)
        plain = column_names.all? { |name| name.is_a?(Symbol) || name.is_a?(String) }
        return pluck_subtree_page(column_names) if subtree_page? && plain

        guarded { super }
      end

      def calculate(...)
        guarded { super }
      end

      def exists?(conditions = :none)
        return subtree_page_ids.any? if conditions == :none && subtree_page?

        guarded { super }
      end

      private

      def guarded(&)
        klass.connection.transaction(requires_new: true, &)
      rescue ActiveRecord::StatementInvalid => e
        match = e.message.match(RecordingStudio::Tree::WALK_ERROR_PATTERN)
        raise RecordingStudio::TreeWalkError, match[0] if match

        raise
      end

      def subtree_page?
        return false unless subtree_seed && limit_value
        return false if reordering_value || distinct_value || lock_value
        return false if where_clause.any? || having_clause.any? || !from_clause.empty?
        return false if select_values.any? || group_values.any?
        return false if includes_values.any? || eager_load_values.any? || preload_values.any?
        return false if left_outer_joins_values.any?

        joins_values.size <= 1
      end

      def subtree_page_ids
        seed = subtree_seed
        RecordingStudio::Tree.subtree_page_ids(
          recording_id: seed.fetch(:recording_id),
          root_recording_id: seed[:root_recording_id],
          include_self: seed.fetch(:include_self),
          limit: limit_value,
          offset: offset_value
        )
      end

      def load_subtree_page(ids = subtree_page_ids)
        @records = if ids.empty?
                     []
                   else
                     by_id = klass.unscoped.where(id: ids).index_by { |record| record.id.to_s }
                     ids.filter_map { |id| by_id[id.to_s] }
                   end
        @loaded = true
      end

      def pluck_subtree_page(column_names)
        ids = subtree_page_ids
        names = column_names.map(&:to_s)
        return ids if names == ["id"]

        load_subtree_page(ids)
        plucked = records.map do |record|
          names.map { |name| record.read_attribute(name) }
        end
        names.one? ? plucked.map(&:first) : plucked
      end
    end

    module_function

    def ancestor_ids(starting_parent_id)
      return [] if starting_parent_id.blank?

      ids_from_walk(walk_rows(ancestor_rows_sql(starting_parent_id)))
    end

    def descendant_ids(recording_id, root_recording_id: nil)
      return [] if recording_id.blank?

      ids_from_walk(walk_rows(descendant_rows_sql(recording_id, root_recording_id: root_recording_id)))
    end

    def subtree_relation(recording_id:, root_recording_id:, include_self:)
      return Recording.unscoped.none if recording_id.blank?

      relation = recordings_joined_to_walk(
        subtree_walk_sql(recording_id, root_recording_id: root_recording_id, include_self: include_self),
        order_by_depth: true
      )
      relation.subtree_seed = {
        recording_id: recording_id,
        root_recording_id: root_recording_id,
        include_self: include_self
      }
      relation
    end

    # One level at a time, each level ordered by id, stopping once the page is
    # full. Children of an in-root recording stay in that root, so the root
    # predicate is only on the first level.
    def subtree_page_ids(recording_id:, root_recording_id:, include_self:, limit:, offset:)
      limit = limit.to_i
      offset = offset.to_i
      return [] if limit <= 0

      needed = limit + [offset, 0].max
      ids = []
      seen = {}
      if include_self
        ids << recording_id
        seen[recording_id] = true
        return ids.drop(offset).first(limit) if ids.size >= needed
      end

      parents = [recording_id]
      seen[recording_id] = true
      depth = 0
      while parents.any? && ids.size < needed
        if depth >= MAX_WALK_DEPTH
          overflow_id = child_ids(parents, root_recording_id: nil, limit: 1).first
          break if overflow_id.nil?

          raise_walk_failure!(overflow_id, cycle: seen[overflow_id])
        end

        remaining = needed - ids.size
        children = child_ids(
          parents,
          root_recording_id: depth.zero? ? root_recording_id : nil,
          limit: remaining + 1
        )
        children.each { |child_id| raise_walk_failure!(child_id, cycle: true) if seen[child_id] }
        taken = children.first(remaining)
        taken.each { |child_id| seen[child_id] = true }
        ids.concat(taken)
        break if children.size > remaining || taken.empty?

        parents = taken
        depth += 1
      end

      ids.drop(offset).first(limit)
    end

    # Distinct parent ids in id order. Each step is one index lookup, and the
    # walk stops after `needed` parents. Callers that pass a limit use this
    # instead of walking every ancestor.
    def child_owner_ids(root_recording_id:, parent_scope:, needed:)
      needed = needed.to_i
      return [] if needed <= 0 || root_recording_id.blank?

      found = []
      cursor = nil
      while found.size < needed
        requested = needed - found.size
        batch = next_child_owner_ids(root_recording_id, after: cursor, limit: requested)
        break if batch.empty?

        cursor = batch.last
        allowed = parent_scope.unscope(:order).where(id: batch).pluck(:id)
        allowed_ids = allowed.to_h { |id| [id, true] }
        batch.each do |id|
          next unless allowed_ids[id]

          found << id
          break if found.size >= needed
        end
        break if batch.size < requested
      end
      found
    end

    def ancestor_ids_of_matches_sql(matching_descendants)
      matches_sql = matching_descendants.unscope(:order).reselect(:id).to_sql
      guarded_walk_sql(ancestor_matches_body(matches_sql), source: "ancestors")
    end

    def connection
      Recording.connection
    end
    private_class_method :connection

    def quote(value)
      connection.quote(value)
    end
    private_class_method :quote

    def walk_rows(sql)
      connection.select_all(sql).to_a
    end
    private_class_method :walk_rows

    def ids_from_walk(rows)
      failed = rows.find { |row| flagged?(row, "cycle") || flagged?(row, "depth_capped") }
      raise TreeWalkError, failure_message(failed) if failed

      rows.map { |row| row.fetch("id") }
    end
    private_class_method :ids_from_walk

    def flagged?(row, name)
      value = row.fetch(name)
      value == true || value.to_i == 1
    end
    private_class_method :flagged?

    def failure_message(row)
      walk_failure_message(row.fetch("id"), cycle: flagged?(row, "cycle"))
    end
    private_class_method :failure_message

    def walk_failure_message(recording_id, cycle:)
      if cycle
        "Recording tree contains a cycle at recording #{recording_id}"
      else
        "Recording tree walk exceeded the depth cap of #{MAX_WALK_DEPTH} at recording #{recording_id}"
      end
    end
    private_class_method :walk_failure_message

    def raise_walk_failure!(recording_id, cycle:)
      raise TreeWalkError, walk_failure_message(recording_id, cycle: cycle)
    end
    private_class_method :raise_walk_failure!

    def child_ids(parent_ids, root_recording_id:, limit:)
      return [] if parent_ids.empty? || limit.to_i <= 0

      parent_sql = if parent_ids.one?
                     "parent_recording_id = #{quote(parent_ids.first)}"
                   else
                     quoted = parent_ids.map { |parent_id| quote(parent_id) }.join(", ")
                     "parent_recording_id IN (#{quoted})"
                   end
      root_sql = "AND root_recording_id = #{quote(root_recording_id)}" if root_recording_id.present?
      connection.select_values(<<~SQL.squish)
        SELECT id
        FROM #{TABLE}
        WHERE #{parent_sql}
          #{root_sql}
        ORDER BY id ASC
        LIMIT #{limit.to_i}
      SQL
    end
    private_class_method :child_ids

    def next_child_owner_ids(root_recording_id, after:, limit:)
      return [] if limit.to_i <= 0

      after_sql = "AND parent_recording_id > #{quote(after)}" if after.present?
      connection.select_values(<<~SQL.squish)
        WITH RECURSIVE parents AS (
          (
            SELECT parent_recording_id AS id, 1 AS n
            FROM #{TABLE}
            WHERE root_recording_id = #{quote(root_recording_id)}
              AND parent_recording_id IS NOT NULL
              #{after_sql}
            ORDER BY parent_recording_id
            LIMIT 1
          )
          UNION ALL
          (
            SELECT nxt.id, parents.n + 1
            FROM parents
            JOIN LATERAL (
              SELECT parent_recording_id AS id
              FROM #{TABLE}
              WHERE root_recording_id = #{quote(root_recording_id)}
                AND parent_recording_id > parents.id
              ORDER BY parent_recording_id
              LIMIT 1
            ) nxt ON TRUE
            WHERE parents.n < #{limit.to_i}
          )
        )
        SELECT id FROM parents
      SQL
    end
    private_class_method :next_child_owner_ids

    def recordings_joined_to_walk(walk_sql, order_by_depth:)
      table = Recording.quoted_table_name
      relation = Recording.unscoped.joins(<<~SQL.squish)
        INNER JOIN (#{walk_sql}) AS recording_walk
          ON recording_walk.id = #{table}.id
      SQL
      relation = relation.order(Arel.sql("recording_walk.depth ASC, #{table}.id ASC")) if order_by_depth
      relation.extending(WalkGuard)
    end
    private_class_method :recordings_joined_to_walk

    def ancestor_rows_sql(starting_parent_id)
      <<~SQL.squish
        WITH RECURSIVE ancestors (
          id, parent_recording_id, depth, path, cycle, depth_capped
        ) AS (
          #{ancestor_body(starting_parent_id)}
        )
        SELECT id, cycle, depth_capped
        FROM ancestors
        ORDER BY depth ASC
      SQL
    end
    private_class_method :ancestor_rows_sql

    def descendant_rows_sql(recording_id, root_recording_id:)
      <<~SQL.squish
        WITH RECURSIVE descendants (
          id, parent_recording_id, depth, path, cycle, depth_capped
        ) AS (
          #{descendant_body(recording_id, root_recording_id)}
        )
        SELECT id, cycle, depth_capped
        FROM descendants
        ORDER BY depth ASC, id ASC
      SQL
    end
    private_class_method :descendant_rows_sql

    def subtree_walk_sql(recording_id, root_recording_id:, include_self:)
      nodes_sql = if include_self
                    <<~SQL.squish
                      SELECT #{quote(recording_id)}::uuid AS id, -1 AS depth, 0 AS cycle, 0 AS depth_capped
                      UNION ALL
                      SELECT id, depth, cycle, depth_capped FROM descendants
                    SQL
                  else
                    "SELECT id, depth, cycle, depth_capped FROM descendants"
                  end
      <<~SQL.squish
        WITH RECURSIVE descendants (
          id, parent_recording_id, depth, path, cycle, depth_capped
        ) AS (
          #{descendant_body(recording_id, root_recording_id)}
        ),
        nodes AS MATERIALIZED (
          #{nodes_sql}
        ),
        guard AS MATERIALIZED (
          #{guard_sql('nodes')}
        )
        SELECT nodes.id, nodes.depth
        FROM nodes
        CROSS JOIN guard
        WHERE nodes.cycle = 0
          AND nodes.depth_capped = 0
          AND guard.ok
      SQL
    end
    private_class_method :subtree_walk_sql

    def guarded_walk_sql(body, source:)
      <<~SQL.squish
        WITH RECURSIVE #{source} (
          id, parent_recording_id, depth, path, cycle, depth_capped
        ) AS (
          #{body}
        ),
        guard AS MATERIALIZED (
          #{guard_sql(source)}
        )
        SELECT #{source}.id
        FROM #{source}
        CROSS JOIN guard
        WHERE #{source}.cycle = 0
          AND #{source}.depth_capped = 0
          AND guard.ok
      SQL
    end
    private_class_method :guarded_walk_sql

    # The root predicate stays on the seed. A child of an in-root recording is
    # already in that root, and repeating the predicate makes Postgres scan the
    # root index once per level. The lateral lookup reads parent_recording_id.
    # OFFSET 0 stops Postgres unnesting that lookup into a hash join.
    def descendant_body(recording_id, root_recording_id)
      root_sql = if root_recording_id.present?
                   "AND child.root_recording_id = #{quote(root_recording_id)}"
                 else
                   ""
                 end
      <<~SQL.squish
        SELECT child.id, child.parent_recording_id, 0, ARRAY[child.id]::uuid[], 0, 0
        FROM #{TABLE} child
        WHERE child.parent_recording_id = #{quote(recording_id)}
          #{root_sql}
        UNION ALL
        SELECT
          child.id,
          child.parent_recording_id,
          descendants.depth + 1,
          descendants.path || child.id,
          CASE WHEN child.id = ANY (descendants.path) THEN 1 ELSE 0 END,
          CASE WHEN descendants.depth + 1 >= #{MAX_WALK_DEPTH} THEN 1 ELSE 0 END
        FROM descendants
        JOIN LATERAL (
          SELECT id, parent_recording_id
          FROM #{TABLE}
          WHERE parent_recording_id = descendants.id
          OFFSET 0
        ) child ON TRUE
        WHERE descendants.cycle = 0
          AND descendants.depth_capped = 0
      SQL
    end
    private_class_method :descendant_body

    def ancestor_body(starting_parent_id)
      <<~SQL.squish
        SELECT recording.id, recording.parent_recording_id, 0, ARRAY[recording.id]::uuid[], 0, 0
        FROM #{TABLE} recording
        WHERE recording.id = #{quote(starting_parent_id)}
        UNION ALL
        #{ancestor_step('ancestors')}
      SQL
    end
    private_class_method :ancestor_body

    def ancestor_matches_body(matches_sql)
      <<~SQL.squish
        SELECT
          parent.id,
          parent.parent_recording_id,
          0,
          ARRAY[child.id, parent.id]::uuid[],
          CASE WHEN parent.id = child.id THEN 1 ELSE 0 END,
          0
        FROM #{TABLE} child
        INNER JOIN #{TABLE} parent ON parent.id = child.parent_recording_id
        WHERE child.id IN (#{matches_sql})
          AND child.parent_recording_id IS NOT NULL
        UNION ALL
        #{ancestor_step('ancestors')}
      SQL
    end
    private_class_method :ancestor_matches_body

    def ancestor_step(source)
      <<~SQL.squish
        SELECT
          parent.id,
          parent.parent_recording_id,
          #{source}.depth + 1,
          #{source}.path || parent.id,
          CASE WHEN parent.id = ANY (#{source}.path) THEN 1 ELSE 0 END,
          CASE WHEN #{source}.depth + 1 >= #{MAX_WALK_DEPTH} THEN 1 ELSE 0 END
        FROM #{source}
        INNER JOIN #{TABLE} parent ON parent.id = #{source}.parent_recording_id
        WHERE #{source}.parent_recording_id IS NOT NULL
          AND #{source}.cycle = 0
          AND #{source}.depth_capped = 0
      SQL
    end
    private_class_method :ancestor_step

    def guard_sql(source)
      cycle_message = quote("Recording tree contains a cycle at recording ")
      depth_message = quote("Recording tree walk exceeded the depth cap of #{MAX_WALK_DEPTH} at recording ")
      <<~SQL.squish
        SELECT CASE
          WHEN notice.message IS NULL THEN TRUE
          ELSE notice.message::uuid IS NULL
        END AS ok
        FROM (
          SELECT (
            SELECT CASE
              WHEN cycle = 1 THEN #{cycle_message} || id::text
              WHEN depth_capped = 1 THEN #{depth_message} || id::text
            END
            FROM #{source}
            WHERE cycle = 1 OR depth_capped = 1
            ORDER BY cycle DESC, depth_capped DESC
            LIMIT 1
          ) AS message
        ) AS notice
      SQL
    end
    private_class_method :guard_sql
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
