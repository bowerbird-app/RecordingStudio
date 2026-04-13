# frozen_string_literal: true

require "cgi"
require "pathname"
require "rack/utils"
require "uri"

module RecordingStudio
  module SafeReturnTo
    module_function

    def sanitize(candidate)
      return if candidate.blank?
      return if candidate.start_with?("//")

      uri = URI.parse(candidate)
      path = sanitize_path(uri.path.to_s)
      return unless path

      query = sanitize_query(uri.query)
      return if uri.query.present? && query.nil?

      build_location(path, query)
    rescue URI::InvalidURIError
      nil
    end

    def sanitize_path(path)
      return unless safe_relative_path?(path)
      return unless safe_relative_path?(CGI.unescape(path))

      path
    end

    def safe_relative_path?(path)
      return false if path.blank?
      return false unless path.start_with?("/")
      return false if path.start_with?("//")

      Pathname.new(path).cleanpath.to_s == path
    end

    def sanitize_query(query)
      return if query.blank?

      Rack::Utils.build_nested_query(Rack::Utils.parse_nested_query(query))
    rescue StandardError
      nil
    end

    def build_location(path, query)
      return path if query.blank?

      "#{path}?#{query}"
    end
  end
end
