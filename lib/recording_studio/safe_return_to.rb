# frozen_string_literal: true

require "cgi"
require "pathname"
require "rack/utils"
require "uri"

module RecordingStudio
  module SafeReturnTo
    module_function

    # Validates and normalizes a redirect target into a safe local path/query string.
    def sanitize(candidate, allowed_prefixes: nil)
      return if candidate.blank?
      return if candidate.start_with?("//")

      uri = parse_uri(candidate)
      return unless uri

      sanitize_uri(uri, allowed_prefixes: allowed_prefixes)
    end

    def parse_uri(candidate)
      URI.parse(candidate)
    rescue URI::InvalidURIError
      nil
    end

    def sanitize_uri(uri, allowed_prefixes:)
      path = sanitize_path(uri.path.to_s)
      return unless path

      query = sanitize_query(uri.query)
      return if uri.query.present? && query.nil?

      build_location(path, query) if allowed_path?(path, allowed_prefixes)
    end

    def sanitize_path(path)
      decoded_path = CGI.unescape(path)
      return unless safe_relative_path?(path)
      return unless safe_relative_path?(decoded_path)
      return if disallowed_path_content?(path)
      return if disallowed_path_content?(decoded_path)
      return if encoded_path_separator?(path)

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
      return if query.match?(/[[:cntrl:]]/)

      Rack::Utils.build_nested_query(Rack::Utils.parse_nested_query(query))
    rescue StandardError
      nil
    end

    def disallowed_path_content?(path)
      path.match?(/[[:cntrl:]\\;]/)
    end

    def encoded_path_separator?(path)
      path.match?(/%(2f|2F|5c|5C|3b|3B)/)
    end

    def allowed_path?(path, allowed_prefixes)
      prefixes = Array(allowed_prefixes).filter_map(&:presence)
      return true if prefixes.empty?

      prefixes.any? { |prefix| allowed_prefix?(path, prefix) }
    end

    def allowed_prefix?(path, prefix)
      return true if prefix == "/" && path == "/"

      path == prefix || path.start_with?("#{prefix}/")
    end

    def build_location(path, query)
      return path if query.blank?

      "#{path}?#{query}"
    end
  end
end
