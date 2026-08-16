# frozen_string_literal: true

module RecordingStudio
  module Metadata
    module_function

    def normalize(metadata, max_bytes: RecordingStudio.configuration.max_metadata_bytes)
      normalized = metadata.presence || {}
      raise ArgumentError, "metadata must be a Hash" unless normalized.is_a?(Hash)

      encoded = encode(normalized)
      limit = Integer(max_bytes)
      if encoded.bytesize > limit
        raise RecordingStudio::MetadataTooLarge,
              "metadata exceeds max_metadata_bytes (#{encoded.bytesize} > #{limit})"
      end

      normalized
    end

    def encode(payload)
      if defined?(ActiveSupport::JSON)
        ActiveSupport::JSON.encode(payload)
      else
        JSON.generate(payload)
      end
    end
    private_class_method :encode
  end
end
