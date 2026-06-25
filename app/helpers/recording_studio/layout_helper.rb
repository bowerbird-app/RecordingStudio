# frozen_string_literal: true

module RecordingStudio
  module LayoutHelper
    PAGE_NAV_SLOT_KEYS = %i[
      page_nav_anchor_url
      page_nav_anchor_icon
      page_nav_anchor_label
      page_nav_back_icon
      page_nav_back_label
      page_nav_back_style
      page_nav_back_size
    ].freeze

    def recording_studio_page_nav(title: nil, **options)
      content_for(:title, title) if title.present?

      PAGE_NAV_SLOT_KEYS.each do |slot_key|
        next unless options.key?(slot_key)

        value = options.fetch(slot_key)
        next if value.nil?

        content_for(slot_key, value)
      end

      nil
    end

    def recording_studio_page_nav_right(&)
      content_for(:page_nav_right, &) if block_given?
      nil
    end

    def recording_studio_head(&)
      content_for(:head, &) if block_given?
      nil
    end

    def recording_studio_seo_description(text)
      content_for(:seo_description, text) if text.present?
      nil
    end

    def recording_studio_seo_image(url)
      content_for(:seo_image, url) if url.present?
      nil
    end
  end
end
