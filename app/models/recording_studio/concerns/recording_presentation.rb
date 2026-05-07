# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module RecordingPresentation
      extend ActiveSupport::Concern

      def name
        RecordingStudio::Labels.name_for(recordable)
      end

      alias label name

      def type_label
        RecordingStudio::Labels.type_label_for(recordable || recordable_type)
      end

      def title
        RecordingStudio::Labels.title_for(recordable)
      end

      def summary
        RecordingStudio::Labels.summary_for(recordable)
      end
    end
  end
end
