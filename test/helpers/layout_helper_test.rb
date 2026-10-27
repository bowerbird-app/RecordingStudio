# frozen_string_literal: true

require "test_helper"

class LayoutHelperTest < ActionView::TestCase
  include RecordingStudio::LayoutHelper

  def test_page_nav_back_row_is_flatpack_not_a_core_helper
    refute_respond_to self, :recording_studio_page_nav
  end

  def test_recording_studio_page_nav_right_sets_slot_and_returns_nil
    result = recording_studio_page_nav_right { tag.a("New note", href: "/notes/new") }

    assert_nil result
    assert_includes content_for(:page_nav_right), "New note"
    assert_includes content_for(:page_nav_right), 'href="/notes/new"'
  end

  def test_default_layout_head_sets_head_slot_content
    default_layout_head { tag.meta(name: "demo", content: "1") }

    assert_includes content_for(:head), "name=\"demo\""
  end

  def test_recording_studio_seo_description_sets_slot
    recording_studio_seo_description("Test description for SEO")

    assert_equal "Test description for SEO", content_for(:seo_description)
  end

  def test_recording_studio_background_image_sets_slot_and_returns_nil
    result = recording_studio_background_image("/icon.png")

    assert_nil result
    assert_equal "/icon.png", content_for(:background_image)
  end

  def test_recording_studio_background_image_skips_a_blank_url
    result = recording_studio_background_image(" ")

    assert_nil result
    assert_predicate content_for(:background_image), :blank?
  end
end
