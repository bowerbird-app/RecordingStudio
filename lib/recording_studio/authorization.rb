# frozen_string_literal: true

module RecordingStudio
  module Authorization
    module_function

    def assert_actor!(actor)
      return actor if actor.present?
      if RecordingStudio.configuration.allow_unauthorized_writes &&
         !RecordingStudio.configuration.require_actor
        return actor
      end

      raise RecordingStudio::ActorRequired,
            "actor is required for RecordingStudio writes"
    end

    def authorize_write!(**context)
      authorizer = RecordingStudio.configuration.authorize_write
      if authorizer.nil?
        return if RecordingStudio.configuration.allow_unauthorized_writes

        raise RecordingStudio::AuthorizationError,
              "RecordingStudio write was denied because config.authorize_write is not configured"
      end

      allowed = authorizer.call(**context)
      return if allowed

      raise RecordingStudio::AuthorizationError, "RecordingStudio write was denied by config.authorize_write"
    end
  end
end
