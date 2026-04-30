# frozen_string_literal: true

module RecordingStudio
  module RecordingTrashableScopes
    extend ActiveSupport::Concern

    included do
      default_scope { where(trashed_at: nil) }

      scope :trashed, -> { unscope(where: :trashed_at).where.not(trashed_at: nil) }
      scope :including_trashed, -> { unscope(where: :trashed_at) }
    end

    class_methods do
      def include_trashed
        including_trashed
      end
    end

    private

    def apply_recordings_query_extensions(scope)
      scope.where(trashed_at: nil)
    end
  end
end
