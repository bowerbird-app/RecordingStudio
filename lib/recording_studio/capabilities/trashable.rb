# frozen_string_literal: true

require_relative "../../../app/models/recording_studio/recording_trashable"
require_relative "../../../app/models/recording_studio/recording_trashable_scopes"
require_relative "../../../app/models/recording_studio/recording_trashable_counters"

module RecordingStudio
  module Capabilities
    module Trashable
      def self.with(include_children: nil)
        Module.new do
          extend ActiveSupport::Concern

          included do |base|
            RecordingStudio::Capabilities::Trashable.configure!(base, include_children: include_children)
          end
        end
      end

      def self.configure!(base, include_children:)
        RecordingStudio.enable_capability(:trashable, on: base.name)
        return if include_children.nil?

        RecordingStudio.set_capability_options(:trashable, on: base.name, include_children: include_children)
      end

      module RecordingMethods
        extend ActiveSupport::Concern

        include RecordingStudio::Capability
        include RecordingStudio::RecordingTrashable
        include RecordingStudio::RecordingTrashableScopes
        include RecordingStudio::RecordingTrashableCounters

        def trash(recording = self, actor: nil, impersonator: nil, metadata: {}, include_children: nil)
          return super if recording.nil?

          assert_capability!(:trashable, for_type: recording.recordable_type)

          super(
            recording,
            actor: actor,
            impersonator: impersonator,
            metadata: metadata,
            include_children: resolve_trash_include_children(recording, include_children)
          )
        end

        def hard_delete(recording = self, actor: nil, impersonator: nil, metadata: {}, include_children: nil)
          return super if recording.nil?

          assert_capability!(:trashable, for_type: recording.recordable_type)

          super(
            recording,
            actor: actor,
            impersonator: impersonator,
            metadata: metadata,
            include_children: resolve_trash_include_children(recording, include_children)
          )
        end

        def restore(recording = self, actor: nil, impersonator: nil, metadata: {}, include_children: nil)
          return super if recording.nil?

          assert_capability!(:trashable, for_type: recording.recordable_type)

          super(
            recording,
            actor: actor,
            impersonator: impersonator,
            metadata: metadata,
            include_children: resolve_trash_include_children(recording, include_children)
          )
        end

        private

        def resolve_trash_include_children(recording, include_children)
          options = RecordingStudio.capability_options(:trashable, for_type: recording.recordable_type) || {}

          include_children ||= options[:include_children]
          include_children ||= RecordingStudio.configuration.include_children
          include_children
        end
      end
    end
  end
end
