# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module RecordableIdentity
      extend ActiveSupport::Concern

      def recordable_type_name
        RecordingStudio.recordable_type_name(recordable || recordable_type)
      end

      def recordable_identifier
        return recordable_id if recordable_id.present?

        RecordingStudio.recordable_identifier(recordable)
      end

      def recordable_global_id
        RecordingStudio.recordable_global_id(recordable)
      end
    end
  end
end
