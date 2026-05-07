# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module RecordingHierarchy
      extend ActiveSupport::Concern

      def root_recording_or_self
        RecordingStudio.root_recording_or_self(self)
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

      def enforce_recordings_scope(scope, root_id:, include_children:)
        constrained = scope.where(root_recording_id: root_id)
        constrained = constrained.where(parent_recording_id: root_id) unless include_children
        constrained
      end

      def assert_recording_belongs_to_root!(recording)
        RecordingStudio.assert_recording_belongs_to_root!(root_recording_or_self, recording)
      end

      def parent_recording_root_consistency
        return if RecordingStudio::Relationships.parent_root_consistent?(self)

        errors.add(:parent_recording_id, "must belong to the same root recording")
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
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
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    end
  end
end
