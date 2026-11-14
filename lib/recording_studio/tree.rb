# frozen_string_literal: true

# The walk SQL is one statement per query. Line length here is the statement, not branching.
# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength
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
    module WalkGuard
      def load
        guarded { super }
      end

      def pluck(*)
        guarded { super }
      end

      def calculate(...)
        guarded { super }
      end

      def exists?(...)
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

      recordings_joined_to_walk(
        subtree_walk_sql(recording_id, root_recording_id: root_recording_id, include_self: include_self),
        order_by_depth: true
      )
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
      recording_id = row.fetch("id")
      if flagged?(row, "cycle")
        "Recording tree contains a cycle at recording #{recording_id}"
      else
        "Recording tree walk exceeded the depth cap of #{MAX_WALK_DEPTH} at recording #{recording_id}"
      end
    end
    private_class_method :failure_message

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
# rubocop:enable Metrics/ModuleLength, Metrics/MethodLength
