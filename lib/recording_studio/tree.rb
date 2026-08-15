# frozen_string_literal: true

module RecordingStudio
  # SQL tree helpers for recording hierarchy traversal.
  # Uses recursive CTEs against PostgreSQL.
  module Tree
    module_function

    def ancestor_ids(starting_parent_id)
      return [] if starting_parent_id.blank?

      sql = <<~SQL.squish
        WITH RECURSIVE ancestors AS (
          SELECT id, parent_recording_id, 0 AS depth
          FROM recording_studio_recordings
          WHERE id = #{quote(starting_parent_id)}
          UNION ALL
          SELECT parent.id, parent.parent_recording_id, ancestors.depth + 1
          FROM recording_studio_recordings parent
          INNER JOIN ancestors ON ancestors.parent_recording_id = parent.id
        )
        SELECT id FROM ancestors ORDER BY depth ASC
      SQL

      connection.select_values(sql)
    end

    def descendant_ids(recording_id, root_recording_id: nil)
      return [] if recording_id.blank?

      root_clause =
        if root_recording_id.present?
          "AND child.root_recording_id = #{quote(root_recording_id)}"
        else
          ""
        end

      sql = <<~SQL.squish
        WITH RECURSIVE descendants AS (
          SELECT id, parent_recording_id, 0 AS depth
          FROM recording_studio_recordings
          WHERE parent_recording_id = #{quote(recording_id)}
          #{"AND root_recording_id = #{quote(root_recording_id)}" if root_recording_id.present?}
          UNION ALL
          SELECT child.id, child.parent_recording_id, descendants.depth + 1
          FROM recording_studio_recordings child
          INNER JOIN descendants ON child.parent_recording_id = descendants.id
          #{root_clause}
        )
        SELECT id FROM descendants ORDER BY depth ASC, id ASC
      SQL

      connection.select_values(sql)
    end

    def parent_links_for_root(root_recording_id)
      return {} if root_recording_id.blank?

      RecordingStudio::Recording
        .unscoped
        .where(root_recording_id: root_recording_id)
        .pluck(:id, :parent_recording_id)
        .to_h
    end

    def ancestor_ids_of_descendants(parent_ids:, matching_descendant_pairs:, parent_links:)
      parent_id_set = parent_ids.to_set
      return [] if parent_id_set.empty?

      matching_descendant_pairs.each_with_object(Set.new) do |(descendant_id, parent_id), acc|
        current_parent_id = parent_id

        while current_parent_id.present?
          acc << current_parent_id if parent_id_set.include?(current_parent_id)
          break if current_parent_id == descendant_id

          current_parent_id = parent_links[current_parent_id]
        end
      end.to_a
    end

    def connection
      RecordingStudio::Recording.connection
    end
    private_class_method :connection

    def quote(value)
      connection.quote(value)
    end
    private_class_method :quote
  end
end
