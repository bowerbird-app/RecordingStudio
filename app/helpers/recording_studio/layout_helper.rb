# frozen_string_literal: true

module RecordingStudio
  module LayoutHelper
    def default_layout_head(&)
      content_for(:head, &) if block_given?
      nil
    end

    def recording_studio_page_nav_right(&)
      content_for(:page_nav_right, &) if block_given?
      nil
    end

    def recording_studio_seo_description(text)
      content_for(:seo_description, text) if text.present?
      nil
    end

    def recording_studio_background_image(url)
      content_for(:background_image, url) if url.present?
      nil
    end

    def recording_studio_page_width(width)
      content_for(:page_width, width.to_s) if width.present?
      nil
    end
  end
end
