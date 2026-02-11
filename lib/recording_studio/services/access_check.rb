# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessCheck < BaseService
      ROLE_ORDER = { "view" => 0, "edit" => 1, "admin" => 2 }.freeze

      def initialize(actor:, recording:, role: nil)
        super()
        @actor = actor
        @recording = recording
        @role = role&.to_s
      end

      private

      def perform
        resolved = resolve_role
        if @role
          success(resolved.present? && ROLE_ORDER.fetch(resolved, -1) >= ROLE_ORDER.fetch(@role, -1))
        else
          success(resolved&.to_sym)
        end
      end

      def resolve_role
        path = []
        boundary = nil
        current = @recording

        # Walk up the recording hierarchy collecting nodes
        while current
          path << current
          if boundary_recording?(current)
            boundary = current
            break
          end
          current = current.parent_recording
        end

        # Check explicit access on the collected path (target → boundary)
        role = find_access_on_path(path)
        return role if role

        if boundary
          boundary_recordable = boundary.recordable
          if boundary_recordable.respond_to?(:minimum_role) && boundary_recordable.minimum_role.present?
            # Continue searching above boundary for actor access
            above_role = find_access_above(boundary) || find_container_access
            if above_role && ROLE_ORDER.fetch(above_role, -1) >= ROLE_ORDER.fetch(boundary_recordable.minimum_role, -1)
              return above_role
            end
          end
          # Boundary with no minimum_role blocks access unless explicit inside (already checked)
          nil
        else
          # No boundary found - check container-level access recordings
          find_container_access
        end
      end

      def boundary_recording?(recording)
        recording.recordable_type == "RecordingStudio::AccessBoundary"
      end

      def find_access_on_path(path)
        path.each do |rec|
          role = find_access_for_recording(rec)
          return role if role
        end
        nil
      end

      def find_access_above(boundary)
        current = boundary.parent_recording
        while current
          role = find_access_for_recording(current)
          return role if role

          # Stop if another boundary is encountered
          break if boundary_recording?(current)

          current = current.parent_recording
        end
        nil
      end

      def find_access_for_recording(recording)
        access = access_recordings_for(recording).first
        access&.recordable&.role
      end

      def find_container_access
        container = @recording.container
        access_recording = RecordingStudio::Recording.unscoped
                                                     .where(container_type: container.class.name, container_id: container.id)
                                                     .where(recordable_type: "RecordingStudio::Access")
                                                     .where(parent_recording_id: nil)
                                                     .where(trashed_at: nil)
                                                     .joins(
                                                       "INNER JOIN recording_studio_accesses ON recording_studio_accesses.id = recording_studio_recordings.recordable_id"
                                                     )
                                                     .where(recording_studio_accesses: { actor_type: @actor.class.name,
                                                                                         actor_id: @actor.id })
                                                     .order("recording_studio_recordings.created_at DESC")
                                                     .first
        return nil unless access_recording

        access_recording.recordable&.role
      end

      def access_recordings_for(recording)
        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: recording.id)
                                  .where(recordable_type: "RecordingStudio::Access")
                                  .where(trashed_at: nil)
                                  .joins(
                                    "INNER JOIN recording_studio_accesses ON recording_studio_accesses.id = recording_studio_recordings.recordable_id"
                                  )
                                  .where(recording_studio_accesses: { actor_type: @actor.class.name,
                                                                      actor_id: @actor.id })
                                  .order("recording_studio_recordings.created_at DESC")
      end

      class << self
        def role_for(actor:, recording:)
          call(actor: actor, recording: recording).value
        end

        def allowed?(actor:, recording:, role:)
          call(actor: actor, recording: recording, role: role).value
        end

        # Returns distinct containers the actor has been granted access to via
        # container-level access recordings (i.e., root recordings where
        # parent_recording_id IS NULL). Recording-level access does not imply
        # container access and is intentionally excluded.
        #
        # @param actor [ActiveRecord::Base] polymorphic actor (e.g., User)
        # @param minimum_role [Symbol,String,nil] optional minimum role threshold
        # @return [Array<Array(String, String)>] array of [container_type, container_id]
        def containers_for(actor:, minimum_role: nil)
          return [] unless actor

          access_scope = RecordingStudio::Access.where(actor_type: actor.class.name, actor_id: actor.id)
          if minimum_role.present?
            minimum_value = RecordingStudio::Access.roles.fetch(minimum_role.to_s)
            access_scope = access_scope.where("role >= ?", minimum_value)
          end

          RecordingStudio::Recording.unscoped
                                    .where(recordable_type: "RecordingStudio::Access")
                                    .where(parent_recording_id: nil)
                                    .where(trashed_at: nil)
                                    .where(recordable_id: access_scope.select(:id))
                                    .distinct
                                    .pluck(:container_type, :container_id)
        end

        # Convenience helper for a single container class.
        # @return [Array<String>] container IDs (UUIDs)
        def container_ids_for(actor:, container_class:, minimum_role: nil)
          return [] unless actor

          container_type = container_class.is_a?(Class) ? container_class.name : container_class.to_s

          access_scope = RecordingStudio::Access.where(actor_type: actor.class.name, actor_id: actor.id)
          if minimum_role.present?
            minimum_value = RecordingStudio::Access.roles.fetch(minimum_role.to_s)
            access_scope = access_scope.where("role >= ?", minimum_value)
          end

          RecordingStudio::Recording.unscoped
                                    .where(container_type: container_type)
                                    .where(recordable_type: "RecordingStudio::Access")
                                    .where(parent_recording_id: nil)
                                    .where(trashed_at: nil)
                                    .where(recordable_id: access_scope.select(:id))
                                    .distinct
                                    .pluck(:container_id)
        end

        def access_recordings_for(recording)
          RecordingStudio::Recording.unscoped
                                    .where(parent_recording_id: recording.id)
                                    .where(recordable_type: "RecordingStudio::Access")
                                    .where(trashed_at: nil)
        end
      end
    end
  end
end
