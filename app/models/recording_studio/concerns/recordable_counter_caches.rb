# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module RecordableCounterCaches
      extend ActiveSupport::Concern

      private

      def update_recordable_counter(recordable_or_type, recordable_id, column, delta)
        RecordingStudio.update_polymorphic_counter(recordable_or_type, recordable_id, column, delta)
      end
    end
  end
end
