# frozen_string_literal: true

module RecordingStudio
  module Capability
    extend ActiveSupport::Concern

    def assert_capability!(name, for_type: recordable_type)
      return if capability_enabled?(name, for_type: for_type)

      raise RecordingStudio::CapabilityDisabled, "Capability :#{name} is not enabled for #{for_type}"
    end

    def capability_enabled?(name, for_type: recordable_type)
      RecordingStudio.capability_enabled?(name, for: for_type)
    end

    def capability_options(name, for_type: recordable_type)
      RecordingStudio.capability_options(name, for: for_type)
    end

    def capabilities(for_type: recordable_type)
      RecordingStudio.capabilities_for(for_type)
    end
  end
end
