# frozen_string_literal: true

require "set"

module RecordingStudio
  module RecordingAccess
    module_function

    def can_view?(grantee, recording_or_recordable)
      matching_access?(grantee, recording_or_recordable) { |access| access.view? || access.edit? }
    end

    def can_edit?(grantee, recording_or_recordable)
      matching_access?(grantee, recording_or_recordable) { |access| access.edit? }
    end

    def matching_access?(grantee, recording_or_recordable)
      return false unless grantee

      each_recording(recording_or_recordable) do |recording|
        access = find_access_for(grantee, recording)
        return yield(access) if access
      end

      false
    end

    def each_recording(recording_or_recordable)
      recordings = recordings_for(recording_or_recordable)
      return if recordings.blank?

      recordings.each { |recording| yield recording }
    end

    def recordings_for(recording_or_recordable)
      return [recording_or_recordable] if recording_or_recordable.is_a?(RecordingStudio::Recording)
      return [] unless recording_or_recordable

      RecordingStudio::Recording.where(
        recordable_type: recording_or_recordable.class.name,
        recordable_id: recording_or_recordable.id
      )
    end
    private_class_method :recordings_for, :each_recording

    def find_access_for(grantee, recording)
      visited = Set.new
      current = recording

      while current
        key = [current.class.name, current.id]
        break if visited.include?(key)

        visited.add(key)

        access = access_for_recording(grantee, current)
        return access if access

        current = current.parent_recording
      end

      nil
    end
    private_class_method :find_access_for, :matching_access?

    def access_for_recording(grantee, recording)
      access = access_for_recordable(grantee, recording) if recording.grants_access?
      return access if access

      recording.child_recordings.of_type(RecordingStudioAccess).each do |child|
        access = access_for_recordable(grantee, child)
        return access if access
      end

      nil
    end

    def access_for_recordable(grantee, recording)
      access = recording.recordable
      return unless access&.grantee_type == grantee.class.name && access.grantee_id == grantee.id

      access
    end
    private_class_method :access_for_recording, :access_for_recordable
  end
end
