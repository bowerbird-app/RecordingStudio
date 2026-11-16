# frozen_string_literal: true

module RecordingStudio
  # Url-safe Base64 JSON cursors shared by Recording and Event keyset pages.
  module KeysetCursor
    module_function

    def encode(payload)
      Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
    end

    def decode(cursor)
      parsed = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
      raise ArgumentError, "cursor is invalid" unless parsed.is_a?(Hash)

      parsed
    rescue ArgumentError, JSON::ParserError
      raise ArgumentError, "cursor is invalid"
    end
  end
end
