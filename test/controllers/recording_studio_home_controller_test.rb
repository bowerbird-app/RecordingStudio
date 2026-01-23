# frozen_string_literal: true

require "test_helper"

class RecordingStudioHomeControllerTest < ActiveSupport::TestCase
  def test_engine_root_renders
    html = RecordingStudio::HomeController.render(:index, layout: false)

    assert_includes html, "RecordingStudio Engine"
  end
end
