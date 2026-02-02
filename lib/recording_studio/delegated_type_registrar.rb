# frozen_string_literal: true

module RecordingStudio
  module DelegatedTypeRegistrar
    def self.apply!
      return unless defined?(ActiveRecord::Base)

      types = Array(RecordingStudio.configuration.recordable_types).map(&:to_s).uniq.sort
      return if types.empty?

      recording_class = if RecordingStudio.const_defined?(:Recording, false)
        RecordingStudio::Recording
      else
        ActiveSupport::Inflector.safe_constantize("RecordingStudio::Recording")
      end
      return unless recording_class
      current_types = recording_class.instance_variable_get(:@recording_studio_recordable_types)
      return if current_types == types

      recording_class.delegated_type :recordable, types: types
      recording_class.instance_variable_set(:@recording_studio_recordable_types, types)

      types.each do |type_name|
        recordable_class = ActiveSupport::Inflector.safe_constantize(type_name)
        next unless recordable_class

        unless recordable_class < ActiveRecord::Base
          next
        end

        unless recordable_class.included_modules.include?(RecordingStudio::Recordable)
          recordable_class.include(RecordingStudio::Recordable)
        end
      end
    end
  end
end
