# frozen_string_literal: true

module RecordingStudio
  module Services
    module AccessCheckClassMethods
      def role_for(actor:, recording:)
        call(actor: actor, recording: recording).value
      end

      def allowed?(actor:, recording:, role:)
        call(actor: actor, recording: recording, role: role).value
      end

      def containers_for(actor:, minimum_role: nil)
        return [] unless actor

        root_access_recordings_for(actor: actor, minimum_role: minimum_role)
          .distinct
          .pluck(:container_type, :container_id)
      end

      def container_ids_for(actor:, container_class:, minimum_role: nil)
        return [] unless actor

        container_type = container_class.is_a?(Class) ? container_class.name : container_class.to_s

        root_access_recordings_for(actor: actor, minimum_role: minimum_role)
          .where(container_type: container_type)
          .distinct
          .pluck(:container_id)
      end

      def access_recordings_for(recording)
        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: recording.id)
                                  .where(recordable_type: "RecordingStudio::Access")
                                  .where(trashed_at: nil)
      end

      private

      def root_access_recordings_for(actor:, minimum_role:)
        access_scope = access_scope_for(actor: actor, minimum_role: minimum_role)
        return RecordingStudio::Recording.none unless access_scope

        RecordingStudio::Recording.unscoped
                                  .where(recordable_type: "RecordingStudio::Access")
                                  .where(parent_recording_id: nil)
                                  .where(trashed_at: nil)
                                  .where(recordable_id: access_scope.select(:id))
      end

      def access_scope_for(actor:, minimum_role:)
        scope = RecordingStudio::Access.where(actor_type: actor.class.name, actor_id: actor.id)
        return scope if minimum_role.blank?

        minimum_value = RecordingStudio::Access.roles[minimum_role.to_s]
        return nil unless minimum_value

        scope.where("role >= ?", minimum_value)
      end
    end
  end
end
