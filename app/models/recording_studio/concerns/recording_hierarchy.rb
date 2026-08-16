# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module RecordingHierarchy
      extend ActiveSupport::Concern

      def root?
        RecordingStudio.root_recording?(self) && RecordingStudio.root_allowed?(recordable_type)
      rescue RecordingStudio::MissingRecordableDeclaration
        false
      end

      def parentless?
        parent_recording_id.blank?
      end

      def orphan?
        parentless? && !root?
      end

      def leaf?
        return false if id.blank?

        !self.class.unscoped.where(parent_recording_id: id).exists?
      end

      def root_recording_or_self
        RecordingStudio.root_recording_or_self(self)
      end

      def ancestors
        return [] if parent_recording_id.blank?

        ancestor_ids = ancestor_id_chain
        ancestors_by_id = self.class.unscoped.where(id: ancestor_ids).index_by(&:id)
        ancestor_ids.reverse.filter_map { |ancestor_id| ancestors_by_id[ancestor_id] }
      end

      def self_and_ancestors
        ancestors + [self]
      end

      def descendants
        return [] if id.blank?

        ids = descendant_id_chain
        return [] if ids.empty?

        recordings_by_id = self.class.unscoped.where(id: ids).index_by(&:id)
        ids.filter_map { |descendant_id| recordings_by_id[descendant_id] }
      end

      def self_and_descendants
        [self] + descendants
      end

      def depth
        ancestors.length
      end

      alias level depth

      private

      def ancestor_id_chain
        RecordingStudio::Tree.ancestor_ids(parent_recording_id)
      end

      def descendant_id_chain
        root_id = RecordingStudio.root_recording_id_for(root_recording_or_self)
        RecordingStudio::Tree.descendant_ids(id, root_recording_id: root_id)
      end

      def assign_root_recording_id
        return if parent_recording_id.nil?

        parent_root_id = self.class.unscoped.where(id: parent_recording_id).pick(:root_recording_id)
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
        persisted_parent = parent_recording_id.present? ? self.class.unscoped.find_by(id: parent_recording_id) : nil
        return if RecordingStudio::Relationships.parent_root_consistent?(self, persisted_parent)

        errors.add(:parent_recording_id, "must belong to the same root recording")
      end

      def parent_recording_must_not_create_cycle # rubocop:disable Metrics/AbcSize
        return if parent_recording_id.nil?

        if id.present? && parent_recording_id == id
          errors.add(:parent_recording_id, "cannot be itself or a descendant recording")
          return
        end

        return if id.blank?

        ancestor_ids = RecordingStudio::Tree.ancestor_ids(parent_recording_id)
        return unless ancestor_ids.map(&:to_s).include?(id.to_s)

        errors.add(:parent_recording_id, "cannot be itself or a descendant recording")
      end
    end
  end
end
