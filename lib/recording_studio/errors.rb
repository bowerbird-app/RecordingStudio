# frozen_string_literal: true

module RecordingStudio
  class IdempotencyError < StandardError; end

  class CapabilityDisabled < StandardError; end

  class RootNotAllowed < StandardError; end

  class InvalidParent < StandardError; end

  class MissingRecordableDeclaration < StandardError; end

  class InvalidRecordableDeclaration < StandardError; end

  class OrphanRecording < InvalidParent; end
end
