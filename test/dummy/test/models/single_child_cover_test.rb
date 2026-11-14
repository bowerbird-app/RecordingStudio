# frozen_string_literal: true

require_relative "../test_helper"

class SingleChildCoverTest < ActiveSupport::TestCase
  test "cover is declared one per parent and the unique index is installed" do
    declaration = RecordingStudio.recordable_declaration_for("RecordingStudioCover")

    assert_equal true, declaration.one_per_parent
    assert_includes RecordingStudio.configuration.recordable_types, "RecordingStudioCover"
    assert_includes RecordingStudio.single_child_index_types, "RecordingStudioCover"

    index = ActiveRecord::Base.connection.indexes(:recording_studio_recordings).find do |candidate|
      candidate.name == "index_recording_studio_recordings_on_single_child"
    end

    assert index
    assert index.unique
    assert_equal %w[parent_recording_id recordable_type], Array(index.columns)
    assert_includes index.where, "RecordingStudioCover"
    refute_match(/trashed/i, index.where.to_s)
  end
end
