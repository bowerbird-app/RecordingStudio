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

    def recording_studio_default_background_image
      configured =
        if RecordingStudio.configuration.respond_to?(:default_background_image)
          RecordingStudio.configuration.default_background_image
        else
          RecordingStudio::DEFAULT_BACKGROUND_IMAGE
        end

      configured.to_s.strip.presence
    end

    def recording_studio_background_image(url = :default)
      image = background_image_source(url)
      content_for(:background_image, image) if image.present?
      nil
    end

    def recording_studio_page_width(width)
      content_for(:page_width, width.to_s) if width.present?
      nil
    end

    private

    def background_image_source(url)
      case url
      when nil, false
        nil
      when true, :default
        recording_studio_default_background_image
      else
        url.is_a?(String) ? url.strip.presence : nil
      end
    end
  end
end
