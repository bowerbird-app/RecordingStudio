# frozen_string_literal: true

require "test_helper"

class LayoutHelperTest < ActionView::TestCase
  include RecordingStudio::LayoutHelper

  def test_recording_studio_page_nav_sets_supported_slots
    recording_studio_page_nav(
      title: "Demo",
      page_nav_anchor_url: "/workspaces",
      page_nav_anchor_icon: "x-mark",
      page_nav_anchor_label: "Close",
      page_nav_back_icon: "arrow-left",
      page_nav_back_label: "Back",
      page_nav_back_style: :ghost,
      page_nav_back_size: :sm
    )

    assert_equal "Demo", content_for(:title)
    assert_equal "/workspaces", content_for(:page_nav_anchor_url)
    assert_equal "x-mark", content_for(:page_nav_anchor_icon)
    assert_equal "Close", content_for(:page_nav_anchor_label)
    assert_equal "arrow-left", content_for(:page_nav_back_icon)
    assert_equal "Back", content_for(:page_nav_back_label)
    assert_equal "ghost", content_for(:page_nav_back_style)
    assert_equal "sm", content_for(:page_nav_back_size)
  end

  def test_recording_studio_page_nav_right_sets_right_slot_content
    recording_studio_page_nav_right { "Right slot action" }

    assert_includes content_for(:page_nav_right), "Right slot action"
  end

  def test_recording_studio_head_sets_head_slot_content
    recording_studio_head { tag.meta(name: "demo", content: "1") }

    assert_includes content_for(:head), "name=\"demo\""
  end
end
