# frozen_string_literal: true

require "test_helper"

class ControlRoomTest < Minitest::Test
  def test_version_exists
    refute_nil ::ControlRoom::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::ControlRoom::Engine
  end
end
