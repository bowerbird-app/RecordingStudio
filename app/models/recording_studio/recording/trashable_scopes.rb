# frozen_string_literal: true

module RecordingStudio
  class Recording < ApplicationRecord
    # Internal module for trash-related scopes and query filtering.
    # Extracted to support future modularization into an addon gem.
    module TrashableScopes
      extend ActiveSupport::Concern

      included do
        scope :trashed, -> { unscope(where: :trashed_at).where.not(trashed_at: nil) }
        scope :including_trashed, -> { unscope(where: :trashed_at) }
      end

      class_methods do
        def include_trashed
          including_trashed
        end
      end

      private

      # Enforce root_recording_id, trashed_at filtering, and optional parent constraint.
      # Used by recordings_query to ensure trash filtering is preserved even after custom scopes.
      def enforce_recordings_scope(scope, root_id:, include_children:)
        constrained = scope.where(root_recording_id: root_id, trashed_at: nil)
        constrained = constrained.where(parent_recording_id: root_id) unless include_children
        constrained
      end
    end
  end
end
