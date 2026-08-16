# frozen_string_literal: true

module RecordingStudio
  module Authorization
    module_function

    def assert_actor!(actor)
      return actor unless RecordingStudio.configuration.require_actor
      return actor if actor.present?

      raise RecordingStudio::ActorRequired,
            "actor is required for RecordingStudio writes when config.require_actor is true"
    end

    def authorize_write!(**context)
      authorizer = RecordingStudio.configuration.authorize_write
      return if authorizer.nil?

      allowed = authorizer.call(**context)
      return if allowed

      raise RecordingStudio::AuthorizationError, "RecordingStudio write was denied by config.authorize_write"
    end
  end
end
