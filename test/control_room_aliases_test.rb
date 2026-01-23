# frozen_string_literal: true

require "test_helper"

class ControlRoomAliasesTest < ActiveSupport::TestCase
  def test_aliases_reference_recording_studio_models
    assert_equal RecordingStudio::Recording, ControlRoom::Recording
    assert_equal RecordingStudio::Event, ControlRoom::Event
    assert_equal RecordingStudio::ApplicationRecord, ControlRoom::ApplicationRecord
  end
end
