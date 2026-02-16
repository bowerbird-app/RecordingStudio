# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module Copyable
      def self.to(*allowed_parent_types)
        type_names = allowed_parent_types.map { |type| type.is_a?(Class) ? type.name : type.to_s }
        Module.new do
          extend ActiveSupport::Concern

          included do |base|
            RecordingStudio.enable_capability(:copyable, on: base.name)
            RecordingStudio.set_capability_options(:copyable, on: base.name, allowed_parent_types: type_names)
          end
        end
      end

      module RecordingMethods
        include RecordingStudio::Capability

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def copy_to!(new_parent:, actor:, impersonator: nil, metadata: {})
          assert_capability!(:copyable)
          assert_recording_belongs_to_root!(new_parent)

          opts = RecordingStudio.capability_options(:copyable, for_type: recordable_type) || {}
          allowed = opts.fetch(:allowed_parent_types, [])
          unless allowed.include?(new_parent.recordable_type)
            raise ArgumentError, "Cannot copy to #{new_parent.recordable_type}; allowed: #{allowed.join(', ')}"
          end

          unless RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: self, role: :view)
            raise RecordingStudio::AccessDenied, "Actor does not have view access on the source recording"
          end

          unless RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: new_parent, role: :edit)
            raise RecordingStudio::AccessDenied, "Actor does not have edit access on the target recording"
          end

          duplicate = duplicate_recordable(recordable)
          duplicate.save!

          RecordingStudio.record!(
            action: "copied",
            recordable: duplicate,
            root_recording: root_recording || self,
            parent_recording: new_parent,
            actor: actor,
            impersonator: impersonator,
            metadata: metadata.merge(
              source_recording_id: id,
              source_recordable_id: recordable_id,
              source_recordable_type: recordable_type
            )
          ).recording
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
      end
    end
  end
end

RecordingStudio.register_capability(:copyable, RecordingStudio::Capabilities::Copyable::RecordingMethods)
