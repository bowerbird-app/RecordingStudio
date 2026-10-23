# frozen_string_literal: true

require "test_helper"

class LayoutHelperTest < ActionView::TestCase
  include RecordingStudio::LayoutHelper

  def test_page_nav_is_flatpack_not_a_core_helper
    refute_respond_to self, :recording_studio_page_nav
    refute_respond_to self, :recording_studio_page_nav_right
  end

  def test_default_layout_head_sets_head_slot_content
    default_layout_head { tag.meta(name: "demo", content: "1") }

    assert_includes content_for(:head), "name=\"demo\""
  end

  def test_recording_studio_seo_description_sets_slot
    recording_studio_seo_description("Test description for SEO")

    assert_equal "Test description for SEO", content_for(:seo_description)
  end
end
