# frozen_string_literal: true

module RecordingStudio
  module Concerns
    module RecordableDuplication
      extend ActiveSupport::Concern

      private

      def duplicate_recordable(recordable)
        RecordingStudio.duplicate_recordable(recordable)
      end
    end
  end
end
