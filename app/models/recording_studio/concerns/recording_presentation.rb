# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module RecordingPresentation
      extend ActiveSupport::Concern

      def name
        label = RecordingStudio::Labels.name_for(presented_recordable)
        return label unless label == RecordingStudio::Labels::EMPTY_LABEL && recordable_type.present?

        RecordingStudio::Labels.type_label_for(recordable_type)
      end

      alias label name

      def type_label
        RecordingStudio::Labels.type_label_for(presented_recordable || recordable_type)
      end

      def title
        RecordingStudio::Labels.title_for(presented_recordable)
      end

      def summary
        RecordingStudio::Labels.summary_for(presented_recordable)
      end

      private

      def presented_recordable
        recordable || typed_recordable
      end

      def typed_recordable
        return if recordable_type.blank?

        association_name = recordable_type.to_s.underscore
        return unless respond_to?(association_name)

        public_send(association_name)
      end
    end
  end
end
