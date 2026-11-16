# frozen_string_literal: true

module RecordingStudio
  # Relation builder for Recording.within.
  #
  # The recording itself is included. A root (parent_recording_id nil) is
  # for_root and does not walk. A nested recording joins Tree.subtree_relation
  # (include_self: true). The walk's depth order and subtree page seed stay
  # off this relation so later of_type, kept, and order clauses still apply.
  # The joined walk still raises TreeWalkError on a cycle or a depth over 1000.
  module RecordingWithin
    RECORDING_ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    module_function

    def apply(scope, recording)
      found = coerce(recording)
      return scope.none if found.nil? || found.id.blank?

      relation = if found.parent_recording_id.nil?
                   scope.for_root(found.id)
                 else
                   join_subtree(scope, found)
                 end
      clear_page_seed(relation)
    end

    def coerce(recording)
      return recording if recording.is_a?(Recording)
      return unless recording.is_a?(String) && recording.match?(RECORDING_ID)

      Recording.unscoped.find_by(id: recording)
    end

    def join_subtree(scope, recording)
      walk = Tree.subtree_relation(
        recording_id: recording.id,
        root_recording_id: recording.root_recording_id,
        include_self: true
      )
      scope.joins(*walk.joins_values).extending(Tree::WalkGuard)
    end

    def clear_page_seed(relation)
      # subtree_relation sets this seed so a plain limited walk can page by
      # depth. That path ignores later where and order clauses. within is a
      # filter, so the seed must not survive onto the relation we return.
      relation.subtree_seed = nil if relation.respond_to?(:subtree_seed=)
      relation
    end
  end
end
