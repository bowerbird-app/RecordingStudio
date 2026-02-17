# frozen_string_literal: true

module RecordingStudio
  class IdempotencyError < StandardError; end

  class AccessDenied < StandardError; end

  class CapabilityDisabled < StandardError; end
end
