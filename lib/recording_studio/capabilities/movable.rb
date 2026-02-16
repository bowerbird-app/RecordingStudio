# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module Movable
      def self.to(*allowed_parent_types)
        type_names = allowed_parent_types.map { |type| type.is_a?(Class) ? type.name : type.to_s }
        Module.new do
          extend ActiveSupport::Concern

          included do |base|
            RecordingStudio.enable_capability(:movable, on: base.name)
            RecordingStudio.set_capability_options(:movable, on: base.name, allowed_parent_types: type_names)
          end
        end
      end

      module RecordingMethods
        include RecordingStudio::Capability

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def move_to!(new_parent:, actor:, impersonator: nil, metadata: {})
          assert_capability!(:movable)
          assert_recording_belongs_to_root!(new_parent)

          opts = RecordingStudio.capability_options(:movable, for_type: recordable_type) || {}
          allowed = opts.fetch(:allowed_parent_types, [])
          unless allowed.include?(new_parent.recordable_type)
            raise ArgumentError, "Cannot move to #{new_parent.recordable_type}; allowed: #{allowed.join(', ')}"
          end

          unless RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: self, role: :edit)
            raise RecordingStudio::AccessDenied, "Actor does not have edit access on the source recording"
          end

          unless RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: new_parent, role: :edit)
            raise RecordingStudio::AccessDenied, "Actor does not have edit access on the target recording"
          end

          from_id = parent_recording_id
          log_event!(
            action: "moved",
            actor: actor,
            impersonator: impersonator,
            metadata: metadata.merge(from_parent_id: from_id, to_parent_id: new_parent.id)
          )
          update!(parent_recording: new_parent)
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
      end
    end
  end
end

RecordingStudio.register_capability(:movable, RecordingStudio::Capabilities::Movable::RecordingMethods)
