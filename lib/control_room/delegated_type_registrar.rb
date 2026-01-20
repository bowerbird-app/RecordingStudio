# frozen_string_literal: true

module ControlRoom
  module DelegatedTypeRegistrar
    def self.apply!
      return unless defined?(ActiveRecord::Base)

      types = Array(ControlRoom.configuration.recordable_types).map(&:to_s).uniq.sort
      return if types.empty?

      recording_class = ControlRoom::Recording
      return if recording_class.respond_to?(:recordable_types) && recording_class.recordable_types == types

      recording_class.delegated_type :recordable, types: types
    end
  end
end
