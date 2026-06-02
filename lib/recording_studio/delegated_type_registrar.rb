# frozen_string_literal: true

module RecordingStudio
  module DelegatedTypeRegistrar
    def self.apply!
      return unless defined?(ActiveRecord::Base)

      RecordingStudio::RecordableDeclarations.install_active_record_macro!
      types = Array(RecordingStudio.configuration.recordable_types).map(&:to_s).uniq.sort
      RecordingStudio.validate_recordable_declarations! unless defer_validation_during_boot?(types)
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

        next unless recordable_class < ActiveRecord::Base

        unless recordable_class.included_modules.include?(RecordingStudio::Recordable)
          recordable_class.include(RecordingStudio::Recordable)
        end
      end
    end

    def self.defer_validation_during_boot?(types)
      return false unless types.any?
      return false unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      return false if Rails.application.initialized?

      types.any? { |type_name| ActiveSupport::Inflector.safe_constantize(type_name).nil? }
    end
  end
end
