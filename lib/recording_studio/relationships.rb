# frozen_string_literal: true

module RecordingStudio
  module Relationships
    module_function

    def root_recording_or_self(recording)
      return if recording.nil?

      recording.root_recording || recording
    end

    def root_recording_id_for(recording)
      return if recording.nil?

      recording.root_recording_id.presence || recording.id
    end

    def root_recording?(recording)
      return false if recording.nil? || recording.id.blank?

      root_recording_id_for(recording) == recording.id
    end

    def same_root?(left_recording, right_recording)
      return true if left_recording.nil? && right_recording.nil?
      return false if left_recording.nil? || right_recording.nil?

      root_recording_id_for(left_recording) == root_recording_id_for(right_recording)
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
