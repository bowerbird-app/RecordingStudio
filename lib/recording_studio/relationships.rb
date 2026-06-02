# frozen_string_literal: true

module RecordingStudio
  module Relationships
    module_function

    def root_recording_or_self(recording)
      return if recording.nil?

      return recording if root_recording?(recording)

      root_recording = recording.root_recording
      return root_recording if root_recording?(root_recording)
    end

    def root_recording_id_for(recording)
      root_recording = root_recording_or_self(recording)
      return if root_recording.nil?

      root_recording.id
    end

    def root_recording?(recording)
      return false if recording.nil? || !recording.persisted?
      return false if recording.parent_recording_id.present?
      return false if recording.root_recording_id.blank?

      recording.root_recording_id == recording.id && RecordingStudio.root_type?(recording.recordable_type)
    end

    def same_root?(left_recording, right_recording)
      return true if left_recording.nil? && right_recording.nil?
      return false if left_recording.nil? || right_recording.nil?

      left_root_id = root_recording_id_for(left_recording)
      right_root_id = root_recording_id_for(right_recording)

      left_root_id.present? && left_root_id == right_root_id
    end

    def assert_root_recording!(recording, message: "root_recording must be a root recording")
      return if root_recording?(recording)

      raise ArgumentError, message
    end

    def recording_belongs_to_root?(recording, root_recording)
      return true if recording.nil?

      same_root?(recording, root_recording)
    end

    def assert_recording_belongs_to_root!(root_recording, recording,
                                          message: "recording must belong to this root recording")
      return if recording_belongs_to_root?(recording, root_recording)

      raise ArgumentError, message
    end

    def assert_parent_recording_belongs_to_root!(parent_recording, root_recording,
                                                 message: "parent_recording must belong to the provided root_recording")
      return if parent_recording.nil?

      assert_recording_belongs_to_root!(root_recording, parent_recording, message: message)
    end

    def parent_root_consistent?(recording, parent_recording = recording&.parent_recording)
      return true if parent_recording.nil?

      my_root_id = recording&.root_recording_id || root_recording_id_for(parent_recording)
      my_root_id == root_recording_id_for(parent_recording)
    end
  end
end
