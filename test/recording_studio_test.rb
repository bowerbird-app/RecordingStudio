# frozen_string_literal: true

require "test_helper"

class RecordingStudioTest < Minitest::Test
  def test_version_exists
    refute_nil ::RecordingStudio::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudio::Engine
  end
end
