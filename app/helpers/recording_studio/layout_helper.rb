# frozen_string_literal: true

module RecordingStudio
  module LayoutHelper
    def default_layout_head(&)
      content_for(:head, &) if block_given?
      nil
    end

    def recording_studio_seo_description(text)
      content_for(:seo_description, text) if text.present?
      nil
    end
  end
end
