# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessCheck < BaseService
      extend AccessCheckClassMethods

      ROLE_ORDER = { "view" => 0, "edit" => 1, "admin" => 2 }.freeze
      ACCESS_JOIN_SQL = <<~SQL.squish.freeze
        INNER JOIN recording_studio_accesses
          ON recording_studio_accesses.id = recording_studio_recordings.recordable_id
      SQL

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
          required_role_value = ROLE_ORDER[@role]
          return success(false) unless required_role_value

          success(resolved.present? && ROLE_ORDER.fetch(resolved, -1) >= required_role_value)
        else
          success(resolved&.to_sym)
        end
      end

      def resolve_role
        path, boundary = recording_path_and_boundary
        role = find_access_on_path(path)
        return role if role

        return find_root_access unless boundary

        resolve_role_with_boundary(boundary)
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

      def find_root_access
        root = @recording.root_recording || @recording
        return nil unless root

        base_access_recording_scope
          .where(root_recording_id: root.id, parent_recording_id: root.id)
          .first&.recordable&.role
      end

      def access_recordings_for(recording)
        base_access_recording_scope.where(parent_recording_id: recording.id)
      end

      def recording_path_and_boundary
        path = []
        current = @recording

        current = collect_non_boundary_path(path, current)
        [path, current]
      end

      def collect_non_boundary_path(path, current)
        while current && !boundary_recording?(current)
          path << current
          current = current.parent_recording
        end
        path << current if current
        current
      end

      def resolve_role_with_boundary(boundary)
        minimum_role = boundary.recordable&.minimum_role
        return nil if minimum_role.blank?

        inherited_role = find_access_above(boundary) || find_root_access
        return nil unless inherited_role

        required_value = ROLE_ORDER.fetch(minimum_role, -1)
        role_value = ROLE_ORDER.fetch(inherited_role, -1)
        role_value >= required_value ? inherited_role : nil
      end

      def base_access_recording_scope
        RecordingStudio::Recording.unscoped
                                  .where(recordable_type: "RecordingStudio::Access")
                                  .where(trashed_at: nil)
                                  .joins(ACCESS_JOIN_SQL)
                                  .where(recording_studio_accesses: { actor_type: @actor.class.name,
                                                                      actor_id: @actor.id })
                                  .order("recording_studio_recordings.created_at DESC")
      end
    end
  end
end
