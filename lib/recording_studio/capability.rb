# frozen_string_literal: true

module RecordingStudio
  module Capability
    extend ActiveSupport::Concern

    private

    def assert_capability!(name)
      return if RecordingStudio.configuration.capability_enabled?(name, for_type: recordable_type)

      raise RecordingStudio::CapabilityDisabled, "Capability :#{name} is not enabled for #{recordable_type}"
    end
  end
end
