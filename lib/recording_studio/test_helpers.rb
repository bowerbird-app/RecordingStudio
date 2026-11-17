# frozen_string_literal: true

module RecordingStudio
  # Assertions for the database root invariant. Require this from a host test
  # helper and include it:
  #
  #   require "recording_studio/test_helpers"
  #
  #   class ActiveSupport::TestCase
  #     include RecordingStudio::TestHelpers
  #   end
  module TestHelpers
    VIOLATIONS_SQL = <<~SQL.squish.freeze
      SELECT recordings.id
      FROM recording_studio_recordings AS recordings
      LEFT JOIN recording_studio_recordings AS parents
        ON parents.id = recordings.parent_recording_id
      WHERE recordings.root_recording_id IS NULL
         OR (
           recordings.parent_recording_id IS NULL
           AND recordings.root_recording_id IS DISTINCT FROM recordings.id
         )
         OR (
           recordings.parent_recording_id IS NOT NULL
           AND recordings.root_recording_id IS DISTINCT FROM parents.root_recording_id
         )
    SQL

    def assert_root_invariant!(message = nil)
      ids = RecordingStudio::TestHelpers.violating_ids
      detail = message || "root_recording_id invariant failed for #{ids.first(5).join(', ')}"
      assert_empty ids, detail
    end

    def self.violating_ids
      RecordingStudio::Recording.connection.select_values(VIOLATIONS_SQL)
    end
  end
end
