# frozen_string_literal: true

module ControlRoom
  module DelegatedTypeRegistrar
    def self.apply!
      return unless defined?(ActiveRecord::Base)

      types = Array(ControlRoom.configuration.recordable_types).map(&:to_s).uniq.sort
      return if types.empty?

      recording_class = if ControlRoom.const_defined?(:Recording, false)
        ControlRoom::Recording
      else
        ActiveSupport::Inflector.safe_constantize("ControlRoom::Recording")
      end
      return unless recording_class
      current_types = recording_class.instance_variable_get(:@control_room_recordable_types)
      return if current_types == types

      recording_class.delegated_type :recordable, types: types
      recording_class.instance_variable_set(:@control_room_recordable_types, types)

      types.each do |type_name|
        recordable_class = ActiveSupport::Inflector.safe_constantize(type_name)
        next unless recordable_class

        unless recordable_class < ActiveRecord::Base
          next
        end

        unless recordable_class.included_modules.include?(ControlRoom::Recordable)
          recordable_class.include(ControlRoom::Recordable)
        end
      end
    end
  end
end
