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

      uri = URI.parse(candidate)
      path = uri.path.to_s
      decoded_path = CGI.unescape(path)

      return if path.blank?
      return unless safe_relative_path?(path)
      return unless safe_relative_path?(decoded_path)

      sanitized_query = sanitize_query(uri.query)
      return if uri.query.present? && sanitized_query.nil?

      path += "?#{sanitized_query}" if sanitized_query.present?
      path
    rescue URI::InvalidURIError
      nil
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
  end
end
