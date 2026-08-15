# frozen_string_literal: true

module RecordingStudio
  class IdempotencyError < StandardError; end

  class CapabilityDisabled < StandardError; end

  class RootNotAllowed < StandardError; end

  class InvalidParent < StandardError; end

  class MissingRecordableDeclaration < StandardError; end

  class InvalidRecordableDeclaration < StandardError; end

  class OrphanRecording < InvalidParent; end

  class MetadataTooLarge < StandardError; end

  class AuthorizationError < StandardError; end

  class ActorRequired < StandardError; end

  class InvalidRevertTarget < ArgumentError; end

  class UnsafeRecordableQuery < ArgumentError; end
end
