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

    def recording_studio_page_nav_right(&block)
      content_for(:page_nav_right, &block) if block_given?
      nil
    end

    def recording_studio_head(&block)
      content_for(:head, &block) if block_given?
      nil
    end
  end
end
